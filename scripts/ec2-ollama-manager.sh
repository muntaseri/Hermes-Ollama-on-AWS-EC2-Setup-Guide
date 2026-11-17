#!/bin/bash

# EC2 Ollama Instance Manager with Elastic IP
# Usage: ./ec2-ollama-manager.sh [start|stop|status|toggle|setup-eip|release-eip]

# Configuration
KEY_NAME="ollama-key"
SECURITY_GROUP="sg-0123456789abcdef0"
AMI_ID="ami-0c55b159cbfafe1f0"
INSTANCE_TYPE="t4g.large"
REGION="us-east-1"

# These will be populated when instance is created
INSTANCE_ID=""
EIP_ID=""

setup_instance() {
    echo "๐��€ Setting up new EC2 instance with Elastic IP..."
    
    # Launch instance
    INSTANCE_ID=$(aws ec2 run-instances \
      --image-id $AMI_ID \
      --instance-type $INSTANCE_TYPE \
      --key-name $KEY_NAME \
      --security-group-ids $SECURITY_GROUP \
      --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ollama}]' \
      --query 'Instances[0].InstanceId' \
      --output text \
      --region $REGION)
    
    echo "๐�“� Instance $INSTANCE_ID created"
    
    # Allocate Elastic IP
    EIP_ID=$(aws ec2 allocate-address \
      --domain vpc \
      --query 'AllocationId' \
      --output text \
      --region $REGION)
    
    echo "๐��ท๏ธ�  Elastic IP $EIP_ID allocated"
    
    # Associate EIP
    aws ec2 associate-address \
      --AllocationId $EIP_ID \
      --InstanceId $INSTANCE_ID \
      --region $REGION
    
    echo "๐�”— Elastic IP associated with instance"
    
    # Store EIP info for later use
    cat > ~/.hermes/eip-info << EOF
INSTANCE_ID=$INSTANCE_ID
EIP_ID=$EIP_ID
EIP_ALLOC_ID=$EIP_ID
EOF
    
    echo "โ�… Setup complete! Instance $INSTANCE_ID"
    echo "๐�’ก Use: ./ec2-ollama-manager.sh status"
}

start_instance() {
    echo "๐��€ Starting EC2 instance..."
    
    # Check if instance exists
    if [[ -z "$INSTANCE_ID" ]]; then
        if [[ -f ~/.hermes/eip-info ]]; then
            source ~/.hermes/eip-info
        else
            echo "โ�� Instance ID not found. Run setup first."
            return 1
        fi
    fi
    
    # Check current status
    STATUS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].State.Name' --output text)
    if [[ "$STATUS" == "running" ]]; then
        echo "โ�… Instance already running"
        return
    fi
    
    # Start instance
    aws ec2 start-instances --instance-ids $INSTANCE_ID --region $REGION
    aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION
    
    # Re-associate Elastic IP (sometimes lost when stopping)
    PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    echo "๐�“� Dynamic IP: $PUBLIC_IP"
    
    # If we have EIP, associate it
    if [[ -n "$EIP_ID" ]]; then
        echo "๐�”� Re-associating Elastic IP..."
        aws ec2 associate-address \
          --AllocationId $EIP_ID \
          --InstanceId $INSTANCE_ID \
          --region $REGION
        PUBLIC_IP=$(aws ec2 describe-addresses --allocation-ids $EIP_ID --query 'Addresses[0].PublicIp' --output text --region $REGION)
        echo "๐��ท๏ธ�  Elastic IP: $PUBLIC_IP"
    fi
    
    echo "๐��� Instance started! IP: $PUBLIC_IP"
    
    # Wait for SSH
    echo "๐�”� Waiting for SSH..."
    timeout 60 bash -c "until ssh -i ~/.ssh/$KEY_NAME.pem ubuntu@$PUBLIC_IP 'echo ready'; do sleep 2; done" && echo "โ�… SSH ready" || echo "โ��๏ธ�  SSH timeout"
    
    echo "๐�’ก Connect with: ssh -i ~/.ssh/$KEY_NAME.pem ubuntu@$PUBLIC_IP"
}

stop_instance() {
    echo "๐��‘ Stopping EC2 instance..."
    
    source ~/.hermes/eip-info
    
    STATUS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].State.Name' --output text)
    if [[ "$STATUS" == "stopped" ]]; then
        echo "โ�… Instance already stopped"
        return
    fi
    
    # Disassociate Elastic IP before stopping
    if [[ -n "$EIP_ID" ]]; then
        echo "๐�”“ Disassociating Elastic IP..."
        aws ec2 disassociate-address --allocation-id $EIP_ID --region $REGION
    fi
    
    # Stop instance
    aws ec2 stop-instances --instance-ids $INSTANCE_ID --region $REGION
    aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID --region $REGION
    
    echo "๐�’ค Instance stopped"
}

status_instance() {
    source ~/.hermes/eip-info
    
    STATUS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].State.Name' --output text)
    PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    
    # Get Elastic IP if available
    EIP=$(aws ec2 describe-addresses --allocation-ids $EIP_ID --query 'Addresses[0].PublicIp' --output text --region $REGION 2>/dev/null || echo "")
    
    echo "๐�“� Instance Status:"
    echo "   State: $STATUS"
    echo "   Dynamic IP: $PUBLIC_IP"
    echo "   ๐��ท๏ธ�  Elastic IP: $EIP"
    
    if [[ "$STATUS" == "running" ]]; then
        echo "   ๐�’ฐ Cost today: ~$(($EIP ? 0.092 : 0)) (t4g.large @ $0.092/hr)"
        echo "   ๐�’ก Connect with: ssh -i ~/.ssh/$KEY_NAME.pem ubuntu@$EIP"
    fi
}

setup_eip() {
    if [[ -z "$INSTANCE_ID" ]]; then
        echo "โ�� Instance ID not found. Start an existing instance first."
        return 1
    fi
    
    STATUS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].State.Name' --output text)
    if [[ "$STATUS" != "stopped" ]]; then
        echo "โ�� Instance must be stopped to allocate EIP. Stop it first."
        return 1
    fi
    
    # Allocate new EIP
    EIP_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text --region $REGION)
    
    # Associate
    aws ec2 associate-address --AllocationId $EIP_ID --InstanceId $INSTANCE_ID --region $REGION
    
    # Update file
    source ~/.hermes/eip-info
    echo "EIP_ID=$EIP_ID" >> ~/.hermes/eip-info
    
    echo "โ�… Elastic IP $EIP_ID allocated and associated"
}

release_eip() {
    source ~/.hermes/eip-info
    
    if [[ -z "$EIP_ID" ]]; then
        echo "โ�� No Elastic IP allocated"
        return 1
    fi
    
    # Disassociate
    aws ec2 disassociate-address --allocation-id $EIP_ID --region $REGION
    
    # Release
    aws ec2 release-address --allocation-id $EIP_ID --region $REGION
    
    # Clean up file
    echo "EIP_ID=" > ~/.hermes/eip-info
    
    echo "โ�… Elastic IP released"
}

cleanup_instance() {
    echo "๐�งน Cleaning up instance and resources..."
    
    source ~/.hermes/eip-info
    
    # Stop instance first
    STATUS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].State.Name' --output text)
    if [[ "$STATUS" == "running" ]]; then
        stop_instance
    fi
    
    # Disassociate and release EIP
    if [[ -n "$EIP_ID" ]]; then
        aws ec2 disassociate-address --allocation-id $EIP_ID --region $REGION 2>/dev/null
        aws ec2 release-address --allocation-id $EIP_ID --region $REGION 2>/dev/null
        echo "๐�—‘๏ธ�  Elastic IP released"
    fi
    
    # Terminate instance
    if [[ -n "$INSTANCE_ID" ]]; then
        aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $REGION
        echo "๐�—‘๏ธ�  Instance $INSTANCE_ID terminated"
    fi
    
    # Clean up
    rm -f ~/.hermes/eip-info
    
    echo "โ�… Cleanup complete"
}

case "$1" in
    setup)
        setup_instance
        ;;
    start)
        start_instance
        ;;
    stop)
        stop_instance
        ;;
    status)
        status_instance
        ;;
    setup-eip)
        setup_eip
        ;;
    release-eip)
        release_eip
        ;;
    cleanup)
        cleanup_instance
        ;;
    toggle)
        source ~/.hermes/eip-info 2>/dev/null || echo "โ��๏ธ�  Run setup or start first"
        STATUS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "not-found")
        
        if [[ "$STATUS" == "running" ]]; then
            stop_instance
        elif [[ "$STATUS" == "running" || "$STATUS" == "not-found" ]]; then
            start_instance
        else
            echo "โ�“ Unknown state: $STATUS"
        fi
        ;;
    *)
        echo "Usage: $0 {setup|start|stop|status|setup-eip|release-eip|cleanup|toggle}"
        echo ""
        echo "Commands:"
        echo "  setup      - Create new instance with Elastic IP (one-time)"
        echo "  start      - Start existing instance"
        echo "  stop       - Stop instance"
        echo "  status     - Check status + Elastic IP"
        echo "  setup-eip  - Allocate EIP to stopped instance"
        echo "  release-eip- Release allocated EIP"
        echo "  cleanup    - Delete instance and EIP"
        echo "  toggle     - Start/stop based on current state"
        echo ""
        echo "๐�’ก First time: ./ec2-ollama-manager.sh setup"
        echo "๐�’ก Then: ./ec2-ollama-manager.sh start"
        ;;
esac
#!/bin/bash

# EC2 Ollama Instance Manager with Ubuntu 26.04 LTS & Elastic IP
# Usage: ./ec2-ollama-manager.sh [setup|start|stop|status|setup-eip|release-eip|cleanup|toggle]

# Configuration
KEY_NAME="ollama-key"
AMI_ID=""  # Will be set via setup or environment (Ubuntu 26.04 LTS)
SECURITY_GROUP="sg-0123456789abcdef0"
INSTANCE_TYPE="t4g.large"
REGION="us-east-1"
EIP_ALLOC_ID=""

setup_instance() {
    echo "🚀 Setting up new EC2 instance with Ubuntu 26.04 LTS & Elastic IP..."
    
    # Use Ubuntu 26.04 LTS AMI (free tier eligible!)
    if [[ -z "$AMI_ID" ]]; then
        echo "💡 Using Ubuntu 26.04 LTS free tier AMI..."
        # Auto-detect based on instance type
        if [[ "$INSTANCE_TYPE" == *"t4g"* ]]; then
            AMI_ID="ami-06b1a03fa3561aefb"  # ARM64
        else
            AMI_ID="ami-0547ecbf0e9b4aeb5"  # x86_64
        fi
    fi
    
    # Validate AMI
    if ! aws ec2 describe-images --image-ids $AMI_ID --region $REGION >/dev/null 2>&1; then
        echo "❌ AMI $AMI_ID not found in this region"
        echo "💡 Set AMI_ID environment variable before running script"
        exit 1
    fi
    
    echo "📋 Using Ubuntu 26.04 LTS AMI: $AMI_ID (free tier eligible!)"
    
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
    
    echo "📋 Instance $INSTANCE_ID created with Ubuntu 26.04 LTS"
    
    # Allocate Elastic IP
    EIP_ALLOC_ID=$(aws ec2 allocate-address \
      --domain vpc \
      --query 'AllocationId' \
      --output text \
      --region $REGION)
    
    echo "🏷️  Elastic IP $EIP_ALLOC_ID allocated"
    
    # Associate EIP
    aws ec2 associate-address \
      --AllocationId $EIP_ALLOC_ID \
      --InstanceId $INSTANCE_ID \
      --region $REGION
    
    echo "🔗 Elastic IP associated with instance"
    
    # Store EIP info for later use
    cat > ~/.hermes/eip-info << EOF
INSTANCE_ID=$INSTANCE_ID
EIP_ALLOC_ID=$EIP_ALLOC_ID
AMI_ID=$AMI_ID
EOF
    
    echo "✅ Setup complete! Instance $INSTANCE_ID with Ubuntu 26.04 LTS"
    echo "💡 Use: ./ec2-ollama-manager.sh status"
}

start_instance() {
    echo "🚀 Starting EC2 instance..."
    
    # Check if instance exists
    if [[ -f ~/.hermes/eip-info ]]; then
        source ~/.hermes/eip-info
    else
        echo "❌ Instance info not found. Run setup first."
        return 1
    fi
    
    # Check current status
    STATUS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].State.Name' --output text)
    if [[ "$STATUS" == "running" ]]; then
        echo "✅ Instance already running"
        return
    fi
    
    # Start instance
    aws ec2 start-instances --instance-ids $INSTANCE_ID --region $REGION
    aws ec2 wait instance-running --instance-ids $INSTANCE_ID --region $REGION
    
    # Re-associate Elastic IP (sometimes lost when stopping)
    PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    echo "📍 Dynamic IP: $PUBLIC_IP"
    
    # If we have EIP, associate it
    if [[ -n "$EIP_ALLOC_ID" ]]; then
        echo "🔄 Re-associating Elastic IP..."
        aws ec2 associate-address \
          --AllocationId $EIP_ALLOC_ID \
          --InstanceId $INSTANCE_ID \
          --region $REGION
        PUBLIC_IP=$(aws ec2 describe-addresses --allocation-ids $EIP_ALLOC_ID --query 'Addresses[0].PublicIp' --output text --region $REGION)
        echo "🏷️  Elastic IP: $PUBLIC_IP"
    fi
    
    echo "🎉 Instance started! IP: $PUBLIC_IP"
    
    # Wait for SSH
    echo "🔐 Waiting for SSH..."
    timeout 60 bash -c "until ssh -i ~/.ssh/$KEY_NAME.pem ubuntu@$PUBLIC_IP 'echo ready'; do sleep 2; done" && echo "✅ SSH ready" || echo "⚠️  SSH timeout"
    
    echo "💡 Connect with: ssh -i ~/.ssh/$KEY_NAME.pem ubuntu@$PUBLIC_IP"
}

stop_instance() {
    echo "🛑 Stopping EC2 instance..."
    
    source ~/.hermes/eip-info
    
    STATUS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].State.Name' --output text)
    if [[ "$STATUS" == "stopped" ]]; then
        echo "✅ Instance already stopped"
        return
    fi
    
    # Disassociate Elastic IP before stopping
    if [[ -n "$EIP_ALLOC_ID" ]]; then
        echo "🔓 Disassociating Elastic IP..."
        aws ec2 disassociate-address --allocation-id $EIP_ALLOC_ID --region $REGION
    fi
    
    # Stop instance
    aws ec2 stop-instances --instance-ids $INSTANCE_ID --region $REGION
    aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID --region $REGION
    
    echo "💤 Instance stopped"
}

status_instance() {
    source ~/.hermes/eip-info
    
    STATUS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].State.Name' --output text)
    PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    
    # Get Elastic IP if available
    EIP=$(aws ec2 describe-addresses --allocation-ids $EIP_ALLOC_ID --query 'Addresses[0].PublicIp' --output text --region $REGION 2>/dev/null || echo "")
    
    echo "📊 Instance Status:"
    echo "   State: $STATUS"
    echo "   Dynamic IP: $PUBLIC_IP"
    echo "   🏷️  Elastic IP: $EIP"
    echo "   📦 AMI: $AMI_ID (Ubuntu 26.04 LTS)"
    
    if [[ "$STATUS" == "running" ]]; then
        echo "   💰 Cost today: ~$(($EIP ? 0.092 : 0)) (t4g.large @ $0.092/hr)"
        echo "   💡 Connect with: ssh -i ~/.ssh/$KEY_NAME.pem ubuntu@$EIP"
    fi
}

setup_eip() {
    if [[ -z "$INSTANCE_ID" ]]; then
        echo "❌ Instance ID not found. Start an existing instance first."
        return 1
    fi
    
    STATUS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].State.Name' --output text)
    if [[ "$STATUS" != "stopped" ]]; then
        echo "❌ Instance must be stopped to allocate EIP. Stop it first."
        return 1
    fi
    
    # Allocate new EIP
    EIP_ALLOC_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text --region $REGION)
    
    # Associate
    aws ec2 associate-address --AllocationId $EIP_ALLOC_ID --InstanceId $INSTANCE_ID --region $REGION
    
    # Update file
    source ~/.hermes/eip-info
    echo "EIP_ALLOC_ID=$EIP_ALLOC_ID" >> ~/.hermes/eip-info
    
    echo "✅ Elastic IP $EIP_ALLOC_ID allocated and associated"
}

release_eip() {
    source ~/.hermes/eip-info
    
    if [[ -z "$EIP_ALLOC_ID" ]]; then
        echo "❌ No Elastic IP allocated"
        return 1
    fi
    
    # Disassociate
    aws ec2 disassociate-address --allocation-id $EIP_ALLOC_ID --region $REGION
    
    # Release
    aws ec2 release-address --allocation-id $EIP_ALLOC_ID --region $REGION
    
    # Clean up file
    echo "EIP_ALLOC_ID=" > ~/.hermes/eip-info
    
    echo "✅ Elastic IP released"
}

cleanup_instance() {
    echo "🧹 Cleaning up instance and resources..."
    
    source ~/.hermes/eip-info
    
    # Stop instance first
    STATUS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].State.Name' --output text)
    if [[ "$STATUS" == "running" ]]; then
        stop_instance
    fi
    
    # Disassociate and release EIP
    if [[ -n "$EIP_ALLOC_ID" ]]; then
        aws ec2 disassociate-address --allocation-id $EIP_ALLOC_ID --region $REGION 2>/dev/null
        aws ec2 release-address --allocation-id $EIP_ALLOC_ID --region $REGION 2>/dev/null
        echo "🗑️  Elastic IP released"
    fi
    
    # Terminate instance
    if [[ -n "$INSTANCE_ID" ]]; then
        aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $REGION
        echo "🗑️  Instance $INSTANCE_ID terminated"
    fi
    
    # Clean up
    rm -f ~/.hermes/eip-info
    
    echo "✅ Cleanup complete"
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
        source ~/.hermes/eip-info 2>/dev/null || echo "⚠️  Run setup or start first"
        STATUS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --region $REGION --query 'Reservations[0].Instances[0].State.Name' --output text 2>/dev/null || echo "not-found")
        
        if [[ "$STATUS" == "running" ]]; then
            stop_instance
        elif [[ "$STATUS" == "running" || "$STATUS" == "not-found" ]]; then
            start_instance
        else
            echo "❓ Unknown state: $STATUS"
        fi
        ;;
    *)
        echo "Usage: $0 {setup|start|stop|status|setup-eip|release-eip|cleanup|toggle}"
        echo ""
        echo "Commands:"
        echo "  setup      - Create new instance with Ubuntu 26.04 LTS & Elastic IP"
        echo "  start      - Start existing instance"
        echo "  stop       - Stop instance"
        echo "  status     - Check status + Elastic IP"
        echo "  setup-eip  - Allocate EIP to stopped instance"
        echo "  release-eip- Release allocated EIP"
        echo "  cleanup    - Delete instance and EIP"
        echo "  toggle     - Start/stop based on current state"
        echo ""
        echo "💡 First time: ./ec2-ollama-manager.sh setup"
        echo "💡 Then: ./ec2-ollama-manager.sh start"
        echo "💡 Ubuntu 26.04 LTS AMI is FREE TIER ELIGIBLE!"
        ;;
esac
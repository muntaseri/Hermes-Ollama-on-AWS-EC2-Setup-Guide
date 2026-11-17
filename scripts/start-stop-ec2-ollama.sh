```bash
#!/bin/bash

INSTANCE_TYPE="t4g.large"
KEY_NAME="ollama-key"
AMI_ID="ami-0c55b159cbfafe1f0"

start_instance() {
    echo "🚀 Starting EC2 instance..."
    aws ec2 start-instances --instance-ids $INSTANCE_ID
    aws ec2 wait instance-running --instance-ids $INSTANCE_ID
    PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    echo "🎉 Instance started! Public IP: $PUBLIC_IP"
}

stop_instance() {
    echo "🛑 Stopping EC2 instance..."
    aws ec2 stop-instances --instance-ids $INSTANCE_ID
    aws ec2 wait instance-stopped --instance-ids $INSTANCE_ID
    echo "💤 Instance stopped"
}

status_instance() {
    STATUS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].State.Name' --output text)
    PUBLIC_IP=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
    echo "📊 Instance Status: $STATUS"
    echo "📍 Public IP: $PUBLIC_IP"
}

case "$1" in
    start) start_instance ;;
    stop) stop_instance ;;
    status) status_instance ;;
    toggle) STATUS=$(aws ec2 describe-instances --instance-ids $INSTANCE_ID --query 'Reservations[0].Instances[0].State.Name' --output text)
            [[ "$STATUS" == "running" ]] && stop_instance || start_instance ;;
    *) echo "Usage: $0 {start|stop|status|toggle}" ;;
esac
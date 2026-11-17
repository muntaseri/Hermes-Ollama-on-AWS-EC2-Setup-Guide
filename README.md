# Hermes + Ollama on AWS EC2 Setup Guide

## Cost-Optimized Instance Recommendation

**Instance:** t4g.large (ARM, 8GB RAM)
- **Hourly rate:** $0.092
- **Monthly cost (80% utilization):** ~$56 for 2 months
- **Total within budget:** $130

**Why t4g.large:**
- Fits within $130 budget for 2 months
- ARM-based AWS Graviton processor
- ARM64 architecture compatible
- Cost-effective alternative to x86 GPU instances

## Setup Process

### 1. Launch EC2 Instance
```bash
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type t4g.large \
  --key-name ollama-key \
  --security-group-ids sg-0123456789abcdef0 \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ollama}]'
```

### 2. Configure Security Group
- Allow SSH (port 22) from your IP
- Allow Ollama API (port 11434) from your Hermes client IP

### 3. Connect via SSH
```bash
ssh -i ~/.ssh/ollama-key.pem ubuntu@<elastic-ip>
```

### 4. Install Dependencies
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Enable and start service
sudo systemctl enable --now ollama

# Optimize Ollama for CPU (ARM)
echo 'Environment="OLLAMA_CPU=1"' | sudo tee -a /etc/systemd/system/ollama.service
sudo systemctl daemon-reload && sudo systemctl restart ollama
```

### 5. Pull Models
```bash
ollama pull gemma:2b
ollama pull llama3:8b
```

### 6. Configure Hermes

**Command line:**
```bash
hermes model
# Select: Custom endpoint (enter URL manually)
# API base URL: http://<ec2-public-ip>:11434/v1
# API key: (leave blank)
# Model name: gemma:2b
```

**Config file:**
```yaml
model:
  default: gemma:2b
  provider: custom
  base_url: http://<ec2-public-ip>:11434/v1
  context_length: 4096
```

## Management Script

### [ec2-ollama-manager.sh (Updated with Elastic IP)](scripts/ec2-ollama-manager.sh)

## Cost Breakdown

**Within $130 Budget (2 months):**
- t4g.large @ $0.092/hr ร— 80% utilization ร— 720 hours = ~$42.05
- EBS storage (100GB gp3): ~$2
- **Total: ~$44** (well under budget!)

**Money-saving tips:**
- Use 80% utilization to stay under budget
- Only pay for active hours when needed
- Consider spot instances for additional savings

## Usage Examples

```bash
# Start when needed
./ec2-ollama-manager.sh start

# Check status and IP
./ec2-ollama-manager.sh status

# Stop when done
./ec2-ollama-manager.sh stop

# Toggle state
./ec2-ollama-manager.sh toggle
```

## Verification

```bash
# From Hermes client
hermes chat
# Should connect to: http://<ec2-ip>:11434/v1

# Test locally (after connecting)
hermes "What's the capital of France?"
```

## Troubleshooting

**SSH issues:**
```bash
# Check security group allows SSH (port 22)
# Check instance is running
aws ec2 describe-instances --instance-ids $INSTANCE_ID
```

**Ollama not starting:**
```bash
sudo systemctl status ollama
sudo journalctl -u ollama
```

**Hermes connection:**
```bash
# Verify endpoint
hermes model
# Should show: http://<ec2-ip>:11434/v1
```

## Alternative Instance Options

If t4g.large doesn't work:
- **g5.xlarge (A10G, 24GB):** $1.006/hr (might exceed budget)
- **c7a.large (AMD, 16GB):** $0.068/hr (cheaper CPU)

## Important Notes

1. **ARM architecture:** t4g.large uses ARM64, ensure compatibility
2. **Data persistence:** Models are stored locally, back up if needed
3. **Monthly costs:** t4g.large is cheapest viable option for Ollama
4. **Budget management:** With 80% utilization, well within $130 budget

## Quick Start Commands

```bash
# 1. Make script executable
chmod +x ec2-ollama-manager.sh

# 2. Start instance
./ec2-ollama-manager.sh start

# 3. Check IP
./ec2-ollama-manager.sh status

# 4. Configure Hermes
hermes model
# Use the IP from status command

# 5. Start using Hermes
hermes chat
```
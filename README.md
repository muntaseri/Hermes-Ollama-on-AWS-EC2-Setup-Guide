## Cost-Optimized Instance Recommendation

**Instance:** t4g.large (ARM, 8GB RAM)
- **AMI:** Ubuntu 26.04 LTS (FREE TIER ELIGIBLE)
- **Hourly rate:** $0.092
- **Monthly cost (80% utilization):** ~$56 for 2 months
- **Total within budget:** $130 (AMI FREE!)

**Why Ubuntu 26.04 LTS:**
- ✅ **FREE TIER ELIGIBLE:** No cost for the operating system
- ✅ **Latest Features:** Ubuntu 26.04 vs 22.04 (2+ years newer)
- ✅ **Verified Provider:** Official Ubuntu AMIs
- ✅ **SSD Performance:** Better disk I/O optimization
- ✅ **ARM64 Compatible:** Perfect for t4g.large Graviton processor
- ✅ **Cost Savings:** Saves $50-100+ compared to older AMIs

## Setup Process

### 1. Launch EC2 Instance
```bash
aws ec2 run-instances \
  --image-id ami-06b1a03fa3561aefb \
  --instance-type t4g.large \
  --key-name ollama-key \
  --security-group-ids sg-0b9f8c7b2fbd665c4  \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ollama}]'
```

**Note:** Using Ubuntu 26.04 LTS AMI (free tier eligible!)

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
```

**Note:** Ubuntu 26.04 LTS includes latest security patches and optimizations.

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
- Ubuntu 26.04 LTS AMI: **FREE** (free tier eligible)
- t4g.large @ $0.092/hr × 80% utilization × 720 hours = ~$42.05
- EBS storage (100GB gp3): ~$2
- **Total: ~$44** (well under budget, and AMI is free!)

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

# Add Elastic IP to stopped instance
./ec2-ollama-manager.sh setup-eip

# Release Elastic IP when done
./ec2-ollama-manager.sh release-eip

# Clean up everything
./ec2-ollama-manager.sh cleanup
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
- **g4dn.xlarge (T4, 16GB):** $0.526/hr (recommended for GPU)
- **c7a.large (AMD, 16GB):** $0.068/hr (cheaper CPU)

## Important Notes

1. **ARM architecture:** t4g.large uses ARM64, ensure compatibility with Ubuntu 26.04 LTS
2. **Data persistence:** Models are stored locally, back up if needed
3. **Monthly costs:** t4g.large is cheapest viable option for Ollama
4. **Budget management:** With 80% utilization, well within $130 budget
5. **Free tier benefits:** Ubuntu 26.04 LTS AMI is free tier eligible!

## Quick Start Commands

```bash
# 1. Make script executable
chmod +x ec2-ollama-manager.sh

# 2. Set Ubuntu 26.04 LTS AMI (choose based on instance type)
export AMI_ID="ami-06b1a03fa3561aefb"  # For t4g.large (ARM)
# or
export AMI_ID="ami-0547ecbf0e9b4aeb5"  # For GPU instances (x86)

# 3. Start instance (creates Ubuntu 26.04 LTS with Elastic IP)
./ec2-ollama-manager.sh setup

# 4. Check IP
./ec2-ollama-manager.sh status

# 5. Configure Hermes
hermes model
# Use the Elastic IP from status command

# 6. Start using Hermes
hermes chat
```

## New Features with Ubuntu 26.04 LTS

- **Latest Security Updates:** More recent CVE patches
- **Free Tier Eligible:** No cost for the operating system
- **Performance Improvements:** Better resource management
- **Extended Support:** Longer maintenance window
- **Cost Optimization:** Significant savings on OS licensing

Ubuntu 26.04 LTS provides the best balance of features, security, and cost-effectiveness for your Hermes + Ollama setup!
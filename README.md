# AFT Quota Manager

Automatically requests AWS service quota increases when new accounts are created through AWS Account Factory for Terraform (AFT).

## What This Does

When a new AWS account is created via AFT, this solution automatically requests quota increases for common services. It's designed to prevent quota-related issues that can block deployments.

### Resources Created
- Lambda function that handles quota requests and monitoring
- SNS topic for sending notifications to Slack
- CloudWatch Events rule that checks quota status every 10 minutes
- IAM roles with minimal permissions for quota management
- KMS key for encrypting logs and messages

## Current Setup

### Deployed Resources
- **Lambda**: `aft-quota-manager-{account-id}` (eu-west-2)
- **SNS Topic**: For Slack notifications
- **Monitoring**: Every 10 minutes via CloudWatch Events

### Quota Status
- **Security Groups**: All regions at 200 (target reached)
- **Elastic IPs**: Requested 20, pending AWS approval

### Supported Regions
- us-east-1, us-west-2, eu-west-1, eu-west-2, ap-southeast-1

## Configuration

Edit `terraform/locals.tf` to change quota settings:

```hcl
target_regions = [
  "us-east-1",
  "us-west-2", 
  "eu-west-1",
  "eu-west-2",
  "ap-southeast-1"
]

quota_config = {
  security_groups = {
    service_code = "vpc"
    quota_code   = "L-0EA8095F"
    quota_value  = 200
    description  = "Security Groups per VPC"
  }
  
  elastic_ips = {
    service_code = "ec2"
    quota_code   = "L-0263D0A3"
    quota_value  = 20
    description  = "Elastic IP addresses per Region"
  }
}
```

## Adding New Quotas

To add a new quota type, add it to the `quota_config` in `terraform/locals.tf`:

```hcl
iam_roles = {
  service_code = "iam"
  quota_code   = "L-FE177D2D"
  quota_value  = 5000
  description  = "IAM Roles per account"
}
```

You'll need to find the correct `service_code` and `quota_code` from the AWS Service Quotas console or API.

## How It Works

1. **Deployment**: AFT automatically deploys when you commit changes
2. **Initial Request**: Lambda requests quota increases for all configured services
3. **Monitoring**: CloudWatch Events trigger Lambda every 10 minutes to check status
4. **Notifications**: When quotas are approved, SNS sends Slack notifications
5. **Logging**: All activity is logged to CloudWatch

## Testing

### Check Current Status
```bash
aws lambda invoke --function-name aft-quota-manager-{account-id} \
  --payload '{"action":"monitor_requests"}' \
  --cli-binary-format raw-in-base64-out response.json
```

### View Logs
```bash
aws logs tail /aws/lambda/aft-quota-manager-{account-id} --follow
```

### Request New Quotas
```bash
aws lambda invoke --function-name aft-quota-manager-{account-id} \
  --payload '{"action":"request_quotas"}' \
  --cli-binary-format raw-in-base64-out response.json
```

## How It Works

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   AFT Account   │───▶│  Lambda Function │───▶│  AWS Service    │
│   Creation      │    │  (Quota Manager) │    │  Quotas API     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                              │
                              ▼
                       ┌──────────────────┐
                       │  CloudWatch      │
                       │  Events (10min)  │
                       └──────────────────┘
                              │
                              ▼
                       ┌──────────────────┐    ┌─────────────────┐
                       │  SNS Topic       │───▶│  Slack Channel  │
                       │  (Notifications) │    │  (#ccoe-notif)  │
                       └──────────────────┘    └─────────────────┘
```

## Monitoring

The system automatically monitors quota requests every 10 minutes. When a quota is approved, you'll get a Slack notification.

You can also check status manually using the AWS CLI commands above.



## Security

- All Lambda logs are encrypted with KMS
- SNS messages are encrypted
- IAM roles use least privilege principle
- No sensitive data is stored

 
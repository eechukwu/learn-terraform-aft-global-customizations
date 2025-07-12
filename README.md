# AFT Quota Manager

Automatically requests AWS service quota increases when new accounts are created through AFT.

## What This Creates

- **Lambda Function**: `aft-quota-manager-*` - Handles quota requests and monitoring
- **SNS Topic**: `aft-quota-notifications-*` - Sends quota notifications
- **SQS Queue**: `aft-quota-lambda-dlq-*` - Dead letter queue for failed Lambda executions
- **CloudWatch Events**: Monitors quota request approvals every 10 minutes
- **IAM Role**: Lambda execution role with Service Quotas permissions
- **KMS Key**: Encrypts Lambda logs and SNS messages

## How It Works

1. **Configuration**: Quota settings are defined in `locals.tf`
2. **Deployment**: AFT automatically deploys when you commit changes
3. **Execution**: Lambda reads quota config from environment variables
4. **Processing**: Requests quota increases for all services across all regions
5. **Monitoring**: CloudWatch Events check approval status every 10 minutes
6. **Notifications**: SNS sends alerts when quotas are approved

## Supported Quota Types

1. Security Groups per VPC (200 limit)
2. IAM Roles per Account (5000 limit)  
3. IAM Customer Managed Policies per Account (1500 limit)

## Configuration

Edit `locals.tf` to configure regions and quota services:

```hcl
target_regions = [
  "us-east-1",
  "us-west-2", 
  "eu-west-1"
]

quota_config = {
  security_groups = {
    service_code = "vpc"
    quota_code   = "L-0EA8095F"
    quota_value  = 200
    description  = "Security Groups per VPC"
  }
  
  iam_roles = {
    service_code = "iam"
    quota_code   = "L-FE177D2D"
    quota_value  = 5000
    description  = "IAM Roles per account"
  }
  
  iam_policies = {
    service_code = "iam"
    quota_code   = "L-0B55BAF2"
    quota_value  = 1500
    description  = "IAM Customer managed policies per account"
  }
}
```

## Adding New Services

Add new services to `locals.tf`:

```hcl
elastic_ips = {
  service_code = "ec2"
  quota_code   = "L-0263D0A3"
  quota_value  = 10
  description  = "Elastic IPs per region"
}
```

## Deployment

This is deployed automatically by AFT when you commit changes to the repository.

## Testing

### Pre-deployment checks:
```bash
./api_helpers/pre-api-helpers.sh
```

### Post-deployment testing (includes automatic monitoring):
```bash
./api_helpers/post-api-helpers.sh
```

### Manual monitoring (optional):
```bash
./api_helpers/quota-monitor.sh
```

## Slack Integration

To enable Slack notifications:

1. Create a Slack bot and get the token
2. Store the token in SSM:
```bash
aws ssm put-parameter \
  --name "/aft/slack/quota-manager-bot-token" \
  --value "xoxb-your-slack-bot-token" \
  --type "SecureString" \
  --overwrite
```

## Monitoring

- CloudWatch logs: `/aws/lambda/aft-quota-manager-*`
- SNS topic: `aft-quota-notifications-*`
- Lambda function: `aft-quota-manager-*`

## Cost

This solution uses free AWS services:
- IAM Roles (always free)
- IAM Policies (always free)
- Security Groups (always free)

No additional costs beyond your existing AWS usage. 
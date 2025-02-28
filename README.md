# Simple Hello World



Terraform
```
export TF_VAR_aws_access_key=your_key
export TF_VAR_aws_secret_key=your_secret
```


```
aws ecr describe-repositories \
  --query 'repositories[*].repositoryName' \
  --output text
```
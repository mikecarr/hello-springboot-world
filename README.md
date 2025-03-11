


# Spring Boot Application Deployment with GitHub Actions and AWS ECR

This repository contains a Spring Boot application that is built and deployed to AWS ECR using GitHub Actions. The containerized application can then be deployed to OpenShift.

## Prerequisites

- AWS Account with ECR repository
- GitHub repository
- OpenShift cluster access
- Docker installed locally (for testing)

## Setting Up GitHub Actions for AWS ECR Deployment

### 1. Create an AWS ECR Repository

First, create your ECR repository in AWS:

```bash
aws ecr create-repository --repository-name fuse-test-services --region us-west-2
```

### 2. Create IAM User for GitHub Actions

Create an IAM user with the necessary permissions to push to ECR:

```bash
# Create policy
aws iam create-policy \
    --policy-name github-actions-ecr-policy \
    --policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "ecr:GetAuthorizationToken",
                    "ecr:BatchCheckLayerAvailability",
                    "ecr:GetDownloadUrlForLayer",
                    "ecr:BatchGetImage",
                    "ecr:InitiateLayerUpload",
                    "ecr:UploadLayerPart",
                    "ecr:CompleteLayerUpload",
                    "ecr:PutImage"
                ],
                "Resource": "*"
            }
        ]
    }'

# Create user and attach policy
aws iam create-user --user-name github-actions-user
aws iam attach-user-policy \
    --user-name github-actions-user \
    --policy-arn $(aws iam list-policies --query 'Policies[?PolicyName==`github-actions-ecr-policy`].Arn' --output text)

# Create access key
aws iam create-access-key --user-name github-actions-user
```

Save the output from the last command - you'll need the `AccessKeyId` and `SecretAccessKey`.

### 3. Set Up GitHub Repository Secrets and Variables

In your GitHub repository, navigate to Settings > Secrets and variables > Actions and add the following:

**Secrets**:
- `AWS_ACCESS_KEY_ID`: Your IAM user AccessKeyId
- `AWS_SECRET_ACCESS_KEY`: Your IAM user SecretAccessKey

**Variables**:
- `AWS_REGION`: `us-west-2` (or your preferred region)
- `ECR_REPOSITORY_NAME`: `fuse-test-services` (the name you created in step 1)

### 4. Create GitHub Actions Workflow File

Create a file at `.github/workflows/build-and-push.yml` with the following content:

```yaml
name: S2I Fuse Java Build
on:
  push:
    branches: [ main, master ]
  pull_request:
    branches: [ main, master ]
jobs:
  s2i-build:
    runs-on: ubuntu-latest
    env:
      # Default values that can be overridden via repository secrets or variables
      PATH_CONTEXT: .
      TLSVERIFY: 'true'
      MAVEN_ARGS_APPEND: ${{ vars.MAVEN_ARGS_APPEND || '' }}
      MAVEN_CLEAR_REPO: ${{ vars.MAVEN_CLEAR_REPO || 'false' }}
      MAVEN_MIRROR_URL: ${{ vars.MAVEN_MIRROR_URL || '' }}
      # ECR related variables
      AWS_REGION: ${{ vars.AWS_REGION || 'us-west-2' }}
      # Base image repository name
      ECR_REPOSITORY: ${{ vars.ECR_REPOSITORY_NAME }}
      # Target repository for the built image
      TARGET_REPOSITORY: fuse-test-services
    steps:
      - name: Check out repository
        uses: actions/checkout@v3
        
      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v2
        
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v2
        with:
          aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
          aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          aws-region: ${{ env.AWS_REGION }}
          
      - name: Login to Amazon ECR
        id: login-ecr
        uses: aws-actions/amazon-ecr-login@v1
        with:
          mask-password: true
        
      - name: Pull base image from ECR
        run: |
          # Get the ECR registry URL
          ECR_REGISTRY=${{ steps.login-ecr.outputs.registry }}
          
          # Extract just the repository name
          REPO_NAME="${{ env.ECR_REPOSITORY }}"
          
          # Construct the proper ECR image URI
          ECR_IMAGE_URI=${ECR_REGISTRY}/${REPO_NAME}:latest
          
          echo "ECR Registry: ${ECR_REGISTRY}"
          echo "Repository Name: ${REPO_NAME}"
          echo "Pulling image from ${ECR_IMAGE_URI}"
          
          # Pull the image
          docker pull ${ECR_IMAGE_URI}
          
          # Store the full image URI for later use
          echo "BASE_IMAGE_URI=${ECR_IMAGE_URI}" >> $GITHUB_ENV
          
          # Verify the image was pulled
          docker images

      - name: Install S2I
        run: |
          curl -s https://api.github.com/repos/openshift/source-to-image/releases/tags/v1.4.0 | \
          grep browser_download_url | \
          grep linux-amd64 | \
          cut -d '"' -f 4 | \
          wget -qi -
          tar -xvf source-to-image*.tar.gz
          sudo mv s2i /usr/local/bin/
          rm -f source-to-image*.tar.gz
          
      - name: Generate environment file
        run: |
          echo "MAVEN_CLEAR_REPO=$MAVEN_CLEAR_REPO" > env-file
          if [[ '${{ env.MAVEN_ARGS_APPEND }}' != "" ]]; then
            echo "MAVEN_ARGS_APPEND=${{ env.MAVEN_ARGS_APPEND }}" >> env-file
          fi
          if [[ '${{ env.MAVEN_MIRROR_URL }}' != "" ]]; then
            echo "MAVEN_MIRROR_URL=${{ env.MAVEN_MIRROR_URL }}" >> env-file
          fi
          echo "Generated Env file"
          echo "------------------------------"
          cat env-file
          echo "------------------------------"
          
      - name: S2I Generate Dockerfile
        run: |
          s2i build ${{ env.PATH_CONTEXT }} ${BASE_IMAGE_URI} \
            --image-scripts-url image:///usr/local/s2i \
            --as-dockerfile ./Dockerfile.gen \
            --environment-file ./env-file
            
      # We don't need a separate login step since we already logged into ECR earlier

      - name: Build and push to ECR
        if: github.event_name != 'pull_request'
        run: |
          # Get the ECR registry URL
          ECR_REGISTRY=${{ steps.login-ecr.outputs.registry }}
          
          # Define target image name with the correct project name
          TARGET_IMAGE="${ECR_REGISTRY}/${{ env.TARGET_REPOSITORY }}:${{ github.sha }}"
          LATEST_TAG="${ECR_REGISTRY}/${{ env.TARGET_REPOSITORY }}:latest"
          
          # Also tag with the proper project name
          PROJECT_TAG="${ECR_REGISTRY}/${{ env.TARGET_REPOSITORY }}:hello-springboot-world"
          
          echo "Building and pushing to ${TARGET_IMAGE}"
          
          # Build using the generated Dockerfile
          docker build -f ./Dockerfile.gen -t ${TARGET_IMAGE} -t ${LATEST_TAG} -t ${PROJECT_TAG} .
          
          # Push the image to ECR
          docker push ${TARGET_IMAGE}
          docker push ${LATEST_TAG}
          docker push ${PROJECT_TAG}
          
          # Save the image URI for later steps
          echo "TARGET_IMAGE=${TARGET_IMAGE}" >> $GITHUB_ENV

      - name: Extract image digest
        if: github.event_name != 'pull_request'
        id: image-digest
        run: |
          DIGEST=$(docker inspect ${TARGET_IMAGE} --format='{{index .RepoDigests 0}}' | cut -d'@' -f2)
          echo "IMAGE_DIGEST=$DIGEST" >> $GITHUB_OUTPUT
          echo "IMAGE_DIGEST=$DIGEST" >> $GITHUB_ENV

      - name: Deploy to environment
        if: github.event_name != 'pull_request'
        run: |
          echo "Deploying image ${TARGET_IMAGE}@${{ env.IMAGE_DIGEST }} to environment..."
          # Add your deployment commands here
          # For example with kubectl:
          # kubectl set image deployment/your-app your-container=${TARGET_IMAGE}@${{ env.IMAGE_DIGEST }}
```

### 5. Prepare Your Spring Boot Project

Update your `pom.xml` to ensure it's compatible with Java 11 (for the `fuse-java-openshift-jdk11-rhel8` base image):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    
    <parent>
        <groupId>org.springframework.boot</groupId>
        <artifactId>spring-boot-starter-parent</artifactId>
        <version>2.7.18</version> <!-- Latest 2.7.x version which is Java 11 compatible -->
        <relativePath/> <!-- lookup parent from repository -->
    </parent>
    
    <groupId>com.mikecarr</groupId>
    <artifactId>hello-springboot-world</artifactId>
    <version>0.0.1-SNAPSHOT</version>
    <name>hello-springboot-world</name>
    <description>Spring Boot Hello World Application</description>
    
    <properties>
        <java.version>11</java.version>
        <maven.compiler.source>11</maven.compiler.source>
        <maven.compiler.target>11</maven.compiler.target>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>
    
    <dependencies>
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-web</artifactId>
        </dependency>
        
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-devtools</artifactId>
            <scope>runtime</scope>
            <optional>true</optional>
        </dependency>
        
        <dependency>
            <groupId>org.springframework.boot</groupId>
            <artifactId>spring-boot-starter-test</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>
    
    <build>
        <finalName>hello-springboot-world</finalName>
        <plugins>
            <plugin>
                <groupId>org.springframework.boot</groupId>
                <artifactId>spring-boot-maven-plugin</artifactId>
            </plugin>
            <plugin>
                <groupId>org.apache.maven.plugins</groupId>
                <artifactId>maven-compiler-plugin</artifactId>
                <configuration>
                    <source>11</source>
                    <target>11</target>
                </configuration>
            </plugin>
        </plugins>
    </build>
</project>
```

### 6. Commit and Push to Your Repository

Commit your workflow file and push to trigger the workflow:

```bash
git add .github/workflows/build-and-push.yml
git add pom.xml
git commit -m "Add GitHub Actions workflow for ECR deployment"
git push
```

## Deploying to OpenShift

Once your image is built and pushed to ECR, you can deploy it to OpenShift.

### 1. Log in to OpenShift

```bash
oc login <your-openshift-cluster-url> --token=<your-token>
```

### 2. Create or Select a Project

```bash
# Create a new project
oc new-project my-springboot-app

# Or select an existing project
oc project my-existing-project
```

### 3. Create a Secret for AWS ECR Authentication

```bash
oc create secret docker-registry ecr-secret \
  --docker-server=$(aws ecr describe-repositories --repository-names fuse-test-services --query 'repositories[0].repositoryUri' --output text | cut -d'/' -f1) \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region us-west-2) \
  --docker-email=your-email@example.com
```

### 4. Link the Secret to Your Default Service Account

```bash
oc secrets link default ecr-secret --for=pull
```

### 5. Create a Deployment YAML

Create a file called `openshift-deployment.yaml`:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-springboot-world
  labels:
    app: hello-springboot-world
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello-springboot-world
  template:
    metadata:
      labels:
        app: hello-springboot-world
    spec:
      containers:
      - name: hello-springboot-world
        image: ${ECR_REGISTRY}/fuse-test-services:latest
        ports:
        - containerPort: 8080
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
          requests:
            cpu: "200m"
            memory: "256Mi"
---
apiVersion: v1
kind: Service
metadata:
  name: hello-springboot-world
spec:
  selector:
    app: hello-springboot-world
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: hello-springboot-world
spec:
  to:
    kind: Service
    name: hello-springboot-world
  port:
    targetPort: 8080
```

Update `${ECR_REGISTRY}` with your actual ECR registry URL.

### 6. Apply the YAML Configuration

```bash
oc apply -f openshift-deployment.yaml
```

### 7. Verify the Deployment

```bash
# Check deployment status
oc get deployments

# Check pods
oc get pods

# Check services and routes
oc get routes
```

### 8. Access Your Application

Get the URL for your application:

```bash
oc get route hello-springboot-world -o jsonpath='{.spec.host}'
```

## Troubleshooting

### Common Issues with GitHub Actions

1. **AWS Credentials Issue**
   - Check if the AWS credentials are set correctly in GitHub Secrets
   - Ensure the IAM user has the right permissions

2. **S2I Build Failure**
   - Verify that the base image exists in ECR
   - Check the logs for any Maven build errors

3. **ECR Push Failure**
   - Ensure the ECR repository exists
   - Check if the GitHub Actions IAM user has push permissions

### Common Issues with OpenShift Deployment

1. **Image Pull Failures**
   - Verify the ECR secret is correctly created
   - Check if the secret is linked to the service account

2. **Application Startup Issues**
   - Check pod logs: `oc logs <pod-name>`
   - Ensure the container port is correctly specified

3. **Route Access Issues**
   - Verify the service is correctly targeting the pods
   - Check if the route is correctly configured

## Additional Resources

- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [AWS ECR Documentation](https://docs.aws.amazon.com/ecr/index.html)
- [S2I (Source-to-Image) Documentation](https://github.com/openshift/source-to-image)
- [OpenShift Documentation](https://docs.openshift.com/)

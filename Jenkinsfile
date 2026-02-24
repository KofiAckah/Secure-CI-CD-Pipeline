pipeline {
    agent any

    environment {
        // AWS & Project Configuration
        AWS_REGION        = 'eu-central-1'
        AWS_ACCOUNT_ID    = credentials('aws-account-id')
        PROJECT_NAME      = 'monitor-spendwise'
        ENVIRONMENT       = 'dev'

        // ECR Repositories
        ECR_REGISTRY      = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        BACKEND_ECR_REPO  = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/monitor-spendwise-backend"
        FRONTEND_ECR_REPO = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/monitor-spendwise-frontend"

        // Image versioning
        IMAGE_TAG = "${env.BUILD_NUMBER}"

        // App Configuration
        APP_REPO_URL = 'https://github.com/KofiAckah/SpendWise-Core-App.git'
        APP_DIR      = '/home/ec2-user/SpendWise'
        BACKEND_PORT = '5000'
    }

    stages {

        // ============================================================
        // Stage 1: Checkout Application Source Code
        // ============================================================
        stage('Checkout') {
            steps {
                echo '=== Checking out SpendWise-Core-App source code ==='
                sh '''
                    rm -rf SpendWise-Core-App
                    git clone https://github.com/KofiAckah/SpendWise-Core-App.git
                '''
                echo '✅ Source code checked out successfully'
            }
        }

        // ============================================================
        // Stage 2: Fetch App Server IPs from AWS
        // ============================================================
        stage('Get App Server IP') {
            steps {
                script {
                    echo '=== Fetching App Server IPs from AWS ==='

                    def privateIp = sh(
                        script: """
                            aws ec2 describe-instances \\
                                --region ${AWS_REGION} \\
                                --filters \\
                                    "Name=tag:Name,Values=${PROJECT_NAME}-${ENVIRONMENT}-app-server" \\
                                    "Name=instance-state-name,Values=running" \\
                                --query 'Reservations[0].Instances[0].PrivateIpAddress' \\
                                --output text
                        """,
                        returnStdout: true
                    ).trim()

                    def publicIp = sh(
                        script: """
                            aws ec2 describe-instances \\
                                --region ${AWS_REGION} \\
                                --filters \\
                                    "Name=tag:Name,Values=${PROJECT_NAME}-${ENVIRONMENT}-app-server" \\
                                    "Name=instance-state-name,Values=running" \\
                                --query 'Reservations[0].Instances[0].PublicIpAddress' \\
                                --output text
                        """,
                        returnStdout: true
                    ).trim()

                    if (!privateIp || privateIp == 'None' || privateIp == '') {
                        error "Could not find running App Server with tag: ${PROJECT_NAME}-${ENVIRONMENT}-app-server"
                    }

                    env.APP_SERVER_PRIVATE_IP = privateIp
                    env.APP_SERVER_PUBLIC_IP  = publicIp

                    echo "✅ App Server Private IP: ${env.APP_SERVER_PRIVATE_IP}"
                    echo "✅ App Server Public IP:  ${env.APP_SERVER_PUBLIC_IP}"
                }
            }
        }

        // ============================================================
        // Stage 3: Run Backend Unit Tests
        // ============================================================
        stage('Run Backend Tests') {
            steps {
                echo '=== Running backend unit tests ==='
                dir('SpendWise-Core-App/backend') {
                    sh '''
                        npm install
                        npm test
                    '''
                }
                echo '✅ All backend tests passed'
            }
        }

        // ============================================================
        // Stage 4: Build Docker Images
        // ============================================================
        stage('Build Docker Images') {
            steps {
                echo '=== Building Docker images ==='
                script {
                    sh """
                        # Inject VITE_API_URL into frontend .env so Vite bakes it in at build time
                        # (The frontend Dockerfile has no ARG for this, but Vite reads .env files)
                        echo 'VITE_API_URL=http://${env.APP_SERVER_PUBLIC_IP}:${BACKEND_PORT}' > SpendWise-Core-App/frontend/.env

                        echo "--- Building backend image (tag: ${IMAGE_TAG}) ---"
                        docker build \\
                            -t ${BACKEND_ECR_REPO}:${IMAGE_TAG} \\
                            -t ${BACKEND_ECR_REPO}:latest \\
                            SpendWise-Core-App/backend

                        echo "--- Building frontend image (tag: ${IMAGE_TAG}) ---"
                        docker build \\
                            -t ${FRONTEND_ECR_REPO}:${IMAGE_TAG} \\
                            -t ${FRONTEND_ECR_REPO}:latest \\
                            SpendWise-Core-App/frontend

                        echo "✅ Both images built successfully (build #${IMAGE_TAG})"
                    """
                }
            }
        }

        // ============================================================
        // Stage 5: Push Images to AWS ECR
        // ============================================================
        stage('Push to ECR') {
            steps {
                echo '=== Authenticating with AWS ECR and pushing images ==='
                script {
                    sh """
                        aws ecr get-login-password --region ${AWS_REGION} | \\
                            docker login --username AWS --password-stdin ${ECR_REGISTRY}

                        echo "--- Pushing backend images ---"
                        docker push ${BACKEND_ECR_REPO}:${IMAGE_TAG}
                        docker push ${BACKEND_ECR_REPO}:latest

                        echo "--- Pushing frontend images ---"
                        docker push ${FRONTEND_ECR_REPO}:${IMAGE_TAG}
                        docker push ${FRONTEND_ECR_REPO}:latest

                        echo "✅ All images pushed to ECR"
                    """
                }
            }
        }

        // ============================================================
        // Stage 6: Deploy to App Server via SSH
        // ============================================================
        stage('Deploy to App Server') {
            steps {
                echo "=== Deploying to App Server (${env.APP_SERVER_PRIVATE_IP}) ==="
                script {
                    sshagent(['ec2-ssh-key']) {
                        sh """
                            ssh -o StrictHostKeyChecking=no ec2-user@${env.APP_SERVER_PRIVATE_IP} << 'ENDSSH'
set -e

echo "--- Authenticating with ECR (via IAM Instance Role) ---"
aws ecr get-login-password --region ${AWS_REGION} | \\
    docker login --username AWS --password-stdin ${ECR_REGISTRY}

echo "--- Pulling new images from ECR ---"
docker pull ${BACKEND_ECR_REPO}:${IMAGE_TAG}
docker pull ${FRONTEND_ECR_REPO}:${IMAGE_TAG}

echo "--- Writing production compose override (uses ECR images, skips build) ---"
printf 'services:\\n  backend:\\n    image: ${BACKEND_ECR_REPO}:${IMAGE_TAG}\\n  frontend:\\n    image: ${FRONTEND_ECR_REPO}:${IMAGE_TAG}\\n' \\
    > ${APP_DIR}/docker-compose.prod.yml

echo "--- Restarting application with new images ---"
cd ${APP_DIR}
docker compose -f docker-compose.yml -f docker-compose.prod.yml down || true
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

echo "✅ Deployment complete"
ENDSSH
                        """
                    }
                }
            }
        }

        // ============================================================
        // Stage 7: Verify Deployment
        // ============================================================
        stage('Verify Deployment') {
            steps {
                echo '=== Waiting for containers to be healthy ==='
                script {
                    sleep(time: 20, unit: 'SECONDS')

                    sshagent(['ec2-ssh-key']) {
                        sh """
                            ssh -o StrictHostKeyChecking=no ec2-user@${env.APP_SERVER_PRIVATE_IP} << 'ENDSSH'
echo "--- Running containers ---"
docker ps --format "table {{.Names}}\\t{{.Status}}\\t{{.Ports}}"

echo ""
echo "--- Backend health check ---"
curl -sf http://localhost:${BACKEND_PORT}/api/health

echo ""
echo "✅ All services are healthy"
ENDSSH
                        """
                    }
                }
            }
        }

        // ============================================================
        // Stage 8: Cleanup Old Images on Jenkins Server
        // ============================================================
        stage('Cleanup Old Images') {
            steps {
                echo '=== Cleaning up old Docker images (keeping last 3 builds) ==='
                script {
                    sh """
                        docker images ${BACKEND_ECR_REPO} --format '{{.Tag}}' | \\
                            grep -E '^[0-9]+\$' | sort -rn | tail -n +4 | \\
                            xargs -r -I{} docker rmi ${BACKEND_ECR_REPO}:{} || true

                        docker images ${FRONTEND_ECR_REPO} --format '{{.Tag}}' | \\
                            grep -E '^[0-9]+\$' | sort -rn | tail -n +4 | \\
                            xargs -r -I{} docker rmi ${FRONTEND_ECR_REPO}:{} || true

                        echo "✅ Cleanup complete"
                    """
                }
            }
        }
    }

    // ============================================================
    // Post-build Actions
    // ============================================================
    post {
        success {
            echo '=========================================='
            echo '✅ Pipeline completed successfully!'
            echo "🌐 SpendWise Frontend : http://${env.APP_SERVER_PUBLIC_IP}"
            echo "🔌 Backend API        : http://${env.APP_SERVER_PUBLIC_IP}:${BACKEND_PORT}/api/health"
            echo '=========================================='
        }
        failure {
            echo '❌ Pipeline failed! Check the console output above for details.'
        }
        always {
            echo '=== Cleaning up workspace and dangling Docker images ==='
            sh 'docker system prune -f || true'
        }
    }
}

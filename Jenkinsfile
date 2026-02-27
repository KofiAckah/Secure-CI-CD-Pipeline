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
        BACKEND_PORT = '5000'

        // ECS Configuration
        ECS_CLUSTER       = 'monitor-spendwise-dev-cluster'
        ECS_SERVICE       = 'monitor-spendwise-dev-service'
        TASK_FAMILY       = 'monitor-spendwise-dev-task'

        // Security Reports Directory
        REPORTS_DIR = 'security-reports'
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
                    mkdir -p security-reports
                '''
                echo '✅ Source code checked out successfully'
            }
        }

        // ============================================================
        // Stage 2: Secret Scanning - Gitleaks
        // ============================================================
        stage('Secret Scan - Gitleaks') {
            steps {
                echo '=== Scanning for hardcoded secrets and credentials ==='
                sh '''
                    docker run --rm \
                        -v ${WORKSPACE}/SpendWise-Core-App:/path \
                        zricethezav/gitleaks:latest \
                        detect \
                        --source /path \
                        --report-format json \
                        --report-path /path/gitleaks-report.json \
                        --exit-code 1 || true

                    cp SpendWise-Core-App/gitleaks-report.json ${REPORTS_DIR}/ 2>/dev/null || true
                '''
                echo '✅ Secret scan complete'
            }
            post {
                always {
                    archiveArtifacts artifacts: 'security-reports/gitleaks-report.json',
                                     allowEmptyArchive: true
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
        // Stage 4: SCA Scan - Snyk Dependency Check
        // ============================================================
        stage('SCA Scan - Snyk') {
            steps {
                echo '=== Scanning dependencies for known vulnerabilities ==='
                withCredentials([string(credentialsId: 'snyk-token', variable: 'SNYK_TOKEN')]) {
                    sh '''
                        docker run --rm \
                            -e SNYK_TOKEN=${SNYK_TOKEN} \
                            -v ${WORKSPACE}/SpendWise-Core-App/backend:/app \
                            snyk/snyk:node \
                            test \
                            --severity-threshold=high \
                            --json \
                            > ${REPORTS_DIR}/snyk-report.json 2>&1 || true

                        echo "Snyk scan complete - check report for findings"
                    '''
                }
                echo '✅ Dependency scan complete'
            }
            post {
                always {
                    archiveArtifacts artifacts: 'security-reports/snyk-report.json',
                                     allowEmptyArchive: true
                }
            }
        }

        // ============================================================
        // Stage 5: SAST Scan - CodeQL
        // ============================================================
        stage('SAST Scan - CodeQL') {
            steps {
                echo '=== Running CodeQL static analysis ==='
                sh '''
                    # Create CodeQL database from backend source
                    /opt/codeql-cli/codeql/codeql database create \
                        ${WORKSPACE}/codeql-db \
                        --language=javascript \
                        --source-root=${WORKSPACE}/SpendWise-Core-App/backend \
                        --overwrite

                    # Run security queries against the database
                    /opt/codeql-cli/codeql/codeql database analyze \
                        ${WORKSPACE}/codeql-db \
                        --format=sarif-latest \
                        --output=${REPORTS_DIR}/codeql-results.sarif \
                        javascript-security-extended

                    echo "CodeQL analysis complete"
                '''
                echo '✅ SAST scan complete'
            }
            post {
                always {
                    archiveArtifacts artifacts: 'security-reports/codeql-results.sarif',
                                     allowEmptyArchive: true
                }
            }
        }

        // ============================================================
        // Stage 6: Build Docker Images
        // ============================================================
        stage('Build Docker Images') {
            steps {
                echo '=== Building Docker images ==='
                sh '''
                    echo "--- Building backend image (tag: ${IMAGE_TAG}) ---"
                    docker build \
                        -t ${BACKEND_ECR_REPO}:${IMAGE_TAG} \
                        -t ${BACKEND_ECR_REPO}:latest \
                        SpendWise-Core-App/backend

                    echo "--- Building frontend image (tag: ${IMAGE_TAG}) ---"
                    docker build \
                        -t ${FRONTEND_ECR_REPO}:${IMAGE_TAG} \
                        -t ${FRONTEND_ECR_REPO}:latest \
                        SpendWise-Core-App/frontend

                    echo "✅ Both images built successfully (build #${IMAGE_TAG})"
                '''
            }
        }

        // ============================================================
        // Stage 7: Image Scan - Trivy
        // ============================================================
        stage('Image Scan - Trivy') {
            steps {
                echo '=== Scanning Docker images for vulnerabilities ==='
                sh '''
                    echo "--- Scanning backend image ---"
                    docker run --rm \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        -v ${WORKSPACE}/${REPORTS_DIR}:/reports \
                        aquasec/trivy:latest image \
                        --exit-code 1 \
                        --severity HIGH,CRITICAL \
                        --format json \
                        --output /reports/trivy-backend-report.json \
                        ${BACKEND_ECR_REPO}:${IMAGE_TAG} || true

                    echo "--- Scanning frontend image ---"
                    docker run --rm \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        -v ${WORKSPACE}/${REPORTS_DIR}:/reports \
                        aquasec/trivy:latest image \
                        --exit-code 1 \
                        --severity HIGH,CRITICAL \
                        --format json \
                        --output /reports/trivy-frontend-report.json \
                        ${FRONTEND_ECR_REPO}:${IMAGE_TAG} || true
                '''
                echo '✅ Image scan complete'
            }
            post {
                always {
                    archiveArtifacts artifacts: 'security-reports/trivy-*-report.json',
                                     allowEmptyArchive: true
                }
            }
        }

        // ============================================================
        // Stage 8: Generate SBOM - Syft
        // ============================================================
        stage('Generate SBOM - Syft') {
            steps {
                echo '=== Generating Software Bill of Materials ==='
                    sh '''
                    echo "--- Generating SBOM for backend image ---"
                    docker run --rm \
                    -v /var/run/docker.sock:/var/run/docker.sock \
                    -v ${WORKSPACE}/security-reports:/output \
                    anchore/syft:latest \
                    docker:${BACKEND_ECR_REPO}:${IMAGE_TAG} \
                    -o cyclonedx-json=/output/sbom-backend.json

                echo "--- Generating SBOM for frontend image ---"
                docker run --rm \
                    -v /var/run/docker.sock:/var/run/docker.sock \
                    -v ${WORKSPACE}/security-reports:/output \
                    anchore/syft:latest \
                    docker:${FRONTEND_ECR_REPO}:${IMAGE_TAG} \
                    -o cyclonedx-json=/output/sbom-frontend.json
            '''
            echo '✅ SBOM generated'
    }
    post {
        always {
            archiveArtifacts artifacts: 'security-reports/sbom-*.json',
                             allowEmptyArchive: true
        }
    }
}


        // ============================================================
        // Stage 9: Push Images to AWS ECR
        // ============================================================
        stage('Push to ECR') {
            steps {
                echo '=== Authenticating with AWS ECR and pushing images ==='
                sh '''
                    aws ecr get-login-password --region ${AWS_REGION} | \
                        docker login --username AWS --password-stdin ${ECR_REGISTRY}

                    echo "--- Pushing backend images ---"
                    docker push ${BACKEND_ECR_REPO}:${IMAGE_TAG}
                    docker push ${BACKEND_ECR_REPO}:latest

                    echo "--- Pushing frontend images ---"
                    docker push ${FRONTEND_ECR_REPO}:${IMAGE_TAG}
                    docker push ${FRONTEND_ECR_REPO}:latest

                    echo "✅ All images pushed to ECR"
                '''
            }
        }

        // ============================================================
        // Stage 10: Deploy to ECS
        // ============================================================
        stage('Deploy to ECS') {
            steps {
                echo '=== Deploying to ECS Fargate ==='
                script {
                    sh '''
                        echo "--- Fetching current task definition ---"
                        aws ecs describe-task-definition \
                            --task-definition ${TASK_FAMILY} \
                            --region ${AWS_REGION} \
                            --query 'taskDefinition' \
                            --output json > current-task-def.json

                        echo "--- Updating image tags in task definition ---"
                        python3 -c "
import json

with open('current-task-def.json') as f:
    td = json.load(f)

for container in td['containerDefinitions']:
    if container['name'] == 'spendwise-backend':
        container['image'] = '${BACKEND_ECR_REPO}:${IMAGE_TAG}'
    if container['name'] == 'spendwise-frontend':
        container['image'] = '${FRONTEND_ECR_REPO}:${IMAGE_TAG}'

# Remove fields AWS does not accept on registration
for key in ['taskDefinitionArn', 'revision', 'status', 'requiresAttributes',
            'compatibilities', 'registeredAt', 'registeredBy']:
    td.pop(key, None)

with open('new-task-def.json', 'w') as f:
    json.dump(td, f)

print('Task definition updated successfully')
"

                        echo "--- Registering new task definition revision ---"
                        NEW_REVISION=$(aws ecs register-task-definition \
                            --region ${AWS_REGION} \
                            --cli-input-json file://new-task-def.json \
                            --query 'taskDefinition.revision' \
                            --output text)

                        echo "Registered revision: $NEW_REVISION"

                        echo "--- Updating ECS service ---"
                        aws ecs update-service \
                            --region ${AWS_REGION} \
                            --cluster ${ECS_CLUSTER} \
                            --service ${ECS_SERVICE} \
                            --task-definition ${TASK_FAMILY}:$NEW_REVISION \
                            --force-new-deployment

                        echo "--- Saving task definition as artifact ---"
                        cp new-task-def.json ${REPORTS_DIR}/task-definition-rendered.json

                        echo "✅ ECS service updated to revision $NEW_REVISION"
                    '''
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'security-reports/task-definition-rendered.json',
                                     allowEmptyArchive: true
                }
            }
        }

        // ============================================================
        // Stage 11: Verify ECS Deployment
        // ============================================================
        stage('Verify ECS Deployment') {
            steps {
                echo '=== Waiting for ECS service to stabilize ==='
                script {
                    sh '''
                        echo "--- Waiting for service to reach steady state ---"
                        aws ecs wait services-stable \
                            --region ${AWS_REGION} \
                            --cluster ${ECS_CLUSTER} \
                            --services ${ECS_SERVICE}

                        echo "--- ECS service status ---"
                        aws ecs describe-services \
                            --region ${AWS_REGION} \
                            --cluster ${ECS_CLUSTER} \
                            --services ${ECS_SERVICE} \
                            --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,TaskDef:taskDefinition}' \
                            --output table

                        echo "✅ ECS deployment verified"
                    '''
                }
            }
        }

        // ============================================================
        // Stage 12: Cleanup Old Images on Jenkins Server
        // ============================================================
        stage('Cleanup Old Images') {
            steps {
                echo '=== Cleaning up old Docker images (keeping last 3 builds) ==='
                sh '''
                    docker images ${BACKEND_ECR_REPO} --format '{{.Tag}}' | \
                        grep -E '^[0-9]+$' | sort -rn | tail -n +4 | \
                        xargs -r -I{} docker rmi ${BACKEND_ECR_REPO}:{} || true

                    docker images ${FRONTEND_ECR_REPO} --format '{{.Tag}}' | \
                        grep -E '^[0-9]+$' | sort -rn | tail -n +4 | \
                        xargs -r -I{} docker rmi ${FRONTEND_ECR_REPO}:{} || true

                    echo "✅ Cleanup complete"
                '''
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
            echo "ECS Cluster : ${ECS_CLUSTER}"
            echo "ECS Service : ${ECS_SERVICE}"
            echo "Image Tag   : ${IMAGE_TAG}"
            echo '=========================================='
        }
        failure {
            echo '❌ Pipeline failed - check security reports in build artifacts'
        }
        always {
            echo '=== Cleaning up workspace and dangling Docker images ==='
            sh '''
                docker system prune -f || true
                rm -f current-task-def.json new-task-def.json || true
            '''
        }
    }
}

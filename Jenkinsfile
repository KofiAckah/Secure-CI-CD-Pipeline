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
                        --exit-code 1
                    GITLEAKS_EXIT=$?

                    cp SpendWise-Core-App/gitleaks-report.json ${REPORTS_DIR}/ 2>/dev/null || true

                    if [ $GITLEAKS_EXIT -ne 0 ]; then
                        echo "❌ Gitleaks detected secrets or credentials — blocking pipeline"
                        exit 1
                    fi
                '''
                echo '✅ No secrets detected'
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
                        # Install snyk in the WORKSPACE root (not inside backend/) so that
                        # snyk's own transitive deps (e.g. minimatch) are never included in
                        # the scan results — only the app's real dependencies are scanned.
                        npm install snyk --save-dev --prefix ${WORKSPACE}/.snyk-cli --loglevel=error
                        SNYK_BIN="${WORKSPACE}/.snyk-cli/node_modules/.bin/snyk"

                        # Authenticate using the Jenkins-stored token
                        ${SNYK_BIN} auth ${SNYK_TOKEN}

                        # Scan only the backend production+dev dependencies.
                        # set +e prevents Jenkins set -e from exiting before we can read $?
                        # exit 0 = clean, exit 1 = HIGH/CRITICAL found, exit 2 = scan error
                        set +e
                        ${SNYK_BIN} test SpendWise-Core-App/backend \
                            --severity-threshold=high \
                            --json \
                            > ${REPORTS_DIR}/snyk-report.json 2>&1
                        SNYK_EXIT=$?
                        set -e

                        if [ $SNYK_EXIT -eq 1 ]; then
                            echo "❌ Snyk found HIGH/CRITICAL vulnerabilities — blocking pipeline"
                            python3 -c "
import json, sys
try:
    data = json.load(open('${REPORTS_DIR}/snyk-report.json'))
    vulns = [v for v in data.get('vulnerabilities', []) if v.get('severity') in ('high', 'critical')]
    print(f'Found {len(vulns)} HIGH/CRITICAL vulnerabilities:')
    for v in vulns[:10]:
        print(f'  [{v[\"severity\"].upper()}] {v[\"id\"]} in {v[\"packageName\"]}@{v[\"version\"]}')
except Exception as e:
    print(f'Could not parse report: {e}')
" || true
                            exit 1
                        elif [ $SNYK_EXIT -eq 2 ]; then
                            echo "❌ Snyk scan error — check token validity and network access"
                            cat ${REPORTS_DIR}/snyk-report.json || true
                            exit 1
                        fi
                        echo "✅ No HIGH/CRITICAL vulnerabilities found"
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
                        ${BACKEND_ECR_REPO}:${IMAGE_TAG}
                    TRIVY_BACKEND_EXIT=$?

                    echo "--- Scanning frontend image ---"
                    docker run --rm \
                        -v /var/run/docker.sock:/var/run/docker.sock \
                        -v ${WORKSPACE}/${REPORTS_DIR}:/reports \
                        aquasec/trivy:latest image \
                        --exit-code 1 \
                        --severity HIGH,CRITICAL \
                        --format json \
                        --output /reports/trivy-frontend-report.json \
                        ${FRONTEND_ECR_REPO}:${IMAGE_TAG}
                    TRIVY_FRONTEND_EXIT=$?

                    # Print summary before failing
                    for img_name in backend frontend; do
                        report="${REPORTS_DIR}/trivy-${img_name}-report.json"
                        if [ -f "$report" ]; then
                            COUNT=$(python3 -c "import json; d=json.load(open('$report')); print(sum(len(r.get('Vulnerabilities') or []) for r in d.get('Results',[])))" 2>/dev/null || echo '?')
                            echo "[$img_name] HIGH/CRITICAL vulnerabilities: $COUNT"
                        fi
                    done

                    if [ $TRIVY_BACKEND_EXIT -ne 0 ] || [ $TRIVY_FRONTEND_EXIT -ne 0 ]; then
                        echo "❌ Trivy found HIGH/CRITICAL vulnerabilities — blocking pipeline"
                        echo "   Remediate the issues and re-run the pipeline"
                        exit 1
                    fi
                    echo "✅ No HIGH/CRITICAL vulnerabilities found in either image"
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
        // Stage 9b: DB Migration — ensure schema exists in RDS
        // ============================================================
        stage('DB Migration') {
            steps {
                echo '=== Running DB schema migration against RDS ==='
                sh '''
                    # Pull DB connection details from SSM (same params ECS uses)
                    DB_HOST=$(aws ssm get-parameter \
                        --name "/${PROJECT_NAME}/${ENVIRONMENT}/app/db_host" \
                        --region ${AWS_REGION} \
                        --query "Parameter.Value" \
                        --output text)

                    DB_USER=$(aws ssm get-parameter \
                        --name "/${PROJECT_NAME}/${ENVIRONMENT}/db/user" \
                        --with-decryption \
                        --region ${AWS_REGION} \
                        --query "Parameter.Value" \
                        --output text)

                    DB_PASS=$(aws ssm get-parameter \
                        --name "/${PROJECT_NAME}/${ENVIRONMENT}/db/password" \
                        --with-decryption \
                        --region ${AWS_REGION} \
                        --query "Parameter.Value" \
                        --output text)

                    DB_NAME=$(aws ssm get-parameter \
                        --name "/${PROJECT_NAME}/${ENVIRONMENT}/db/name" \
                        --region ${AWS_REGION} \
                        --query "Parameter.Value" \
                        --output text)

                    echo "Running init.sql against RDS host: $DB_HOST"

                    # Use postgres client container (same VPC, Jenkins SG now allowed in RDS SG)
                    docker run --rm \
                        -e PGPASSWORD="$DB_PASS" \
                        -v ${WORKSPACE}/SpendWise-Core-App/backend:/sql \
                        postgres:16-alpine \
                        psql \
                            --host="$DB_HOST" \
                            --port=5432 \
                            --username="$DB_USER" \
                            --dbname="$DB_NAME" \
                            --file=/sql/init.sql \
                            --no-password

                    echo "✅ DB migration complete"
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
                // 8 minutes max — 24 attempts × 15s = 360s
                // ECS circuit breaker takes ~3-5 min to mark COMPLETED even when container is healthy
                timeout(time: 8, unit: 'MINUTES') {
                    script {
                        sh '''
                            echo "--- Waiting for service to reach steady state ---"
                            STABLE_COUNT=0
                            # Poll every 15s for up to 8 minutes (24 attempts).
                            for i in $(seq 1 24); do
                                ROLLOUT=$(aws ecs describe-services \
                                    --region ${AWS_REGION} \
                                    --cluster ${ECS_CLUSTER} \
                                    --services ${ECS_SERVICE} \
                                    --no-cli-pager \
                                    --query 'services[0].deployments[?status==`PRIMARY`].rolloutState | [0]' \
                                    --output text)

                                RUNNING=$(aws ecs describe-services \
                                    --region ${AWS_REGION} \
                                    --cluster ${ECS_CLUSTER} \
                                    --services ${ECS_SERVICE} \
                                    --no-cli-pager \
                                    --query 'services[0].deployments[?status==`PRIMARY`].runningCount | [0]' \
                                    --output text)

                                DESIRED=$(aws ecs describe-services \
                                    --region ${AWS_REGION} \
                                    --cluster ${ECS_CLUSTER} \
                                    --services ${ECS_SERVICE} \
                                    --no-cli-pager \
                                    --query 'services[0].deployments[?status==`PRIMARY`].desiredCount | [0]' \
                                    --output text)

                                echo "Attempt $i/24 — running=$RUNNING desired=$DESIRED rolloutState=$ROLLOUT"

                                # ECS circuit breaker marks COMPLETED ~3-5 min after tasks are healthy
                                if [ "$ROLLOUT" = "COMPLETED" ] && [ "$RUNNING" = "$DESIRED" ]; then
                                    echo "✅ Deployment COMPLETED — service is stable"
                                    break
                                fi

                                if [ "$ROLLOUT" = "FAILED" ]; then
                                    echo "❌ Deployment FAILED — circuit breaker rolled back"
                                    echo "--- Last 5 ECS service events ---"
                                    aws ecs describe-services \
                                        --region ${AWS_REGION} \
                                        --cluster ${ECS_CLUSTER} \
                                        --services ${ECS_SERVICE} \
                                        --no-cli-pager \
                                        --query 'services[0].events[:5]' \
                                        --output table
                                    exit 1
                                fi

                                # Secondary success: running==desired for 2 consecutive checks means
                                # the container is healthy even if circuit breaker hasn't finalized yet
                                if [ "$DESIRED" -gt "0" ] 2>/dev/null && [ "$RUNNING" = "$DESIRED" ]; then
                                    STABLE_COUNT=$((STABLE_COUNT + 1))
                                    echo "  ↳ Stable check $STABLE_COUNT/2 (running==desired, waiting for COMPLETED)"
                                    if [ "$STABLE_COUNT" -ge "2" ]; then
                                        echo "✅ Service stable — running=$RUNNING desired=$DESIRED (circuit breaker still evaluating)"
                                        break
                                    fi
                                else
                                    STABLE_COUNT=0
                                fi

                                sleep 15
                            done

                            echo "--- Final ECS service state ---"
                            aws ecs describe-services \
                                --region ${AWS_REGION} \
                                --cluster ${ECS_CLUSTER} \
                                --services ${ECS_SERVICE} \
                                --no-cli-pager \
                                --query 'services[0].{Status:status,Running:runningCount,Desired:desiredCount,TaskDef:taskDefinition}' \
                                --output table
                        '''
                    }
                }
            }
        }

        // ============================================================
        // Stage 12: Update Prometheus ECS Scrape Target
        // ============================================================
        // After each ECS deploy the task gets a new private IP.
        // Prometheus uses file_sd_configs reading ecs_targets.json on the
        // monitoring server — this stage rewrites that file via SSH so
        // Prometheus auto-discovers the new backend without a service reload.
        //
        // PREREQUISITE: Add the SpendWise PEM key to Jenkins as an
        // "SSH Username with private key" credential with ID: monitoring-server-key
        // (username: ubuntu, private key: contents of SpendWise-KP.pem)
        // ============================================================
        stage('Update Prometheus ECS Target') {
            steps {
                echo '=== Updating Prometheus ECS scrape target ==='
                withCredentials([sshUserPrivateKey(credentialsId: 'ec2-ssh-key',
                                                   keyFileVariable: 'MONITORING_KEY',
                                                   usernameVariable: 'MONITORING_USER')]) {
                    sh '''
                        # --- Discover the current ECS task private IP ---
                        # Use describe-tasks containers[].networkInterfaces directly.
                        # This avoids needing ec2:DescribeNetworkInterfaces.
                        TASK_ARN=$(aws ecs list-tasks \
                            --region ${AWS_REGION} \
                            --cluster ${ECS_CLUSTER} \
                            --query 'taskArns[0]' \
                            --no-cli-pager \
                            --output text)

                        ECS_IP=$(aws ecs describe-tasks \
                            --region ${AWS_REGION} \
                            --cluster ${ECS_CLUSTER} \
                            --tasks ${TASK_ARN} \
                            --no-cli-pager \
                            --query 'tasks[0].containers[0].networkInterfaces[0].privateIpv4Address' \
                            --output text)

                        echo "ECS backend private IP: ${ECS_IP}"

                        # --- Write new ecs_targets.json on monitoring server ---
                        # Prometheus file_sd auto-reloads this file every 30s.
                        # No prometheus restart needed.
                        TARGETS_JSON=$(printf '[{"targets":["%s:5000"],"labels":{"service":"spendwise-backend","environment":"dev"}}]' "${ECS_IP}")

                        ssh -o StrictHostKeyChecking=no \
                            -o ConnectTimeout=10 \
                            -i "${MONITORING_KEY}" \
                            ubuntu@52.57.3.18 \
                            "echo '${TARGETS_JSON}' | sudo tee /etc/prometheus/ecs_targets.json > /dev/null && echo '✅ ecs_targets.json updated'"

                        echo "✅ Prometheus will scrape ${ECS_IP}:5000 within 30 seconds"
                    '''
                }
            }
        }

        // ============================================================
        // Stage 13: Cleanup Old Images on Jenkins Server
        // ============================================================
        stage('Cleanup Old Images') {
            steps {
                echo '=== Cleaning up old Docker images and ECS task revisions ==='
                sh '''
                    # ── Local Jenkins Docker images (keep last 3 builds) ──────────
                    docker images ${BACKEND_ECR_REPO} --format '{{.Tag}}' | \
                        grep -E '^[0-9]+$' | sort -rn | tail -n +4 | \
                        xargs -r -I{} docker rmi ${BACKEND_ECR_REPO}:{} || true

                    docker images ${FRONTEND_ECR_REPO} --format '{{.Tag}}' | \
                        grep -E '^[0-9]+$' | sort -rn | tail -n +4 | \
                        xargs -r -I{} docker rmi ${FRONTEND_ECR_REPO}:{} || true

                    # ── ECR images are managed by lifecycle policy (keeps last 5) ─
                    echo "ECR lifecycle policy manages remote image retention automatically"

                    # ── Deregister old ECS task definition revisions (keep last 3) ─
                    echo "--- Deregistering old ECS task definition revisions ---"
                    ALL_REVISIONS=$(aws ecs list-task-definitions \
                        --region ${AWS_REGION} \
                        --family-prefix ${TASK_FAMILY} \
                        --status ACTIVE \
                        --no-cli-pager \
                        --query 'taskDefinitionArns' \
                        --output text | tr '\t' '\n' | sort -t: -k7 -rn)

                    KEEP=3
                    COUNT=0
                    for ARN in $ALL_REVISIONS; do
                        COUNT=$((COUNT + 1))
                        if [ $COUNT -gt $KEEP ]; then
                            echo "Deregistering old revision: $ARN"
                            aws ecs deregister-task-definition \
                                --task-definition $ARN \
                                --region ${AWS_REGION} \
                                --no-cli-pager > /dev/null
                        fi
                    done

                    echo "✅ Cleanup complete (kept last $KEEP task definition revisions)"
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
            sh '''
                aws cloudwatch put-metric-data \
                    --region ${AWS_REGION} \
                    --namespace "monitor-spendwise/dev" \
                    --metric-name DeploymentSuccess \
                    --value 1 \
                    --unit Count \
                    --dimensions Pipeline=spendwise-cicd,Build=${IMAGE_TAG} || true
            '''
        }
        failure {
            echo '❌ Pipeline failed - check security reports in build artifacts'
            sh '''
                aws cloudwatch put-metric-data \
                    --region ${AWS_REGION} \
                    --namespace "monitor-spendwise/dev" \
                    --metric-name DeploymentFailures \
                    --value 1 \
                    --unit Count \
                    --dimensions Pipeline=spendwise-cicd,Build=${IMAGE_TAG} || true
            '''
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

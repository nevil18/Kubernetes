pipeline {
    agent {
        label 'project-finbot'
    }

    environment {
        DOCKERHUB_USERNAME = 'nevilanghan'
        DOCKERHUB_CREDENTIALS = credentials('dockerhub-creds')
        REPO_URL = 'https://github.com/nevil18/Kubernetes.git'
        K8S_DIR = '/home/ubuntu/project/CKsFinBot/k8s'
    }

    triggers {
        githubPush()
    }

    stages {

        stage('Clone Repository') {
            steps {
                git branch: 'main',
                    url: "${REPO_URL}"
            }
        }

        stage('Detect Changes') {
            steps {
                script {
                    def changedFiles = sh(
                        script: "git diff --name-only HEAD~1 HEAD",
                        returnStdout: true
                    ).trim()

                    echo "Changed files: ${changedFiles}"

                    env.BUILD_FRONTEND     = changedFiles.contains('Frontend/') ? 'true' : 'false'
                    env.BUILD_NODE_BACKEND = changedFiles.contains('Node-Backend/') ? 'true' : 'false'
                    env.BUILD_PYTHON       = changedFiles.contains('Python-Backend/') ? 'true' : 'false'
                    env.BUILD_MONGO        = changedFiles.contains('k8s/mongo') ? 'true' : 'false'

                    echo "Build Frontend: ${env.BUILD_FRONTEND}"
                    echo "Build Node Backend: ${env.BUILD_NODE_BACKEND}"
                    echo "Build Python Backend: ${env.BUILD_PYTHON}"
                    echo "Build Mongo: ${env.BUILD_MONGO}"
                }
            }
        }

        stage('Docker Login') {
            steps {
                sh "echo ${DOCKERHUB_CREDENTIALS_PSW} | docker login -u ${DOCKERHUB_CREDENTIALS_USR} --password-stdin"
            }
        }

        stage('Frontend - Build, Push & Clean') {
            when {
                expression { env.BUILD_FRONTEND == 'true' }
            }
            steps {
                sh """
                    echo "🔨 Building Frontend..."
                    cd ${WORKSPACE}/CKsFinBot/Frontend
                    docker build --no-cache --network host -t ${DOCKERHUB_USERNAME}/cksfinbot-frontend:latest .
                    echo "📤 Pushing Frontend..."
                    docker push ${DOCKERHUB_USERNAME}/cksfinbot-frontend:latest
                    echo "🧹 Cleaning Frontend image..."
                    docker rmi ${DOCKERHUB_USERNAME}/cksfinbot-frontend:latest || true
                    docker image prune -f || true
                """
            }
        }

        stage('Node Backend - Build, Push & Clean') {
            when {
                expression { env.BUILD_NODE_BACKEND == 'true' }
            }
            steps {
                sh """
                    echo "🔨 Building Node Backend..."
                    cd ${WORKSPACE}/CKsFinBot/Node-Backend
                    docker build --no-cache --network host -t ${DOCKERHUB_USERNAME}/cksfinbot-node-backend:latest .
                    echo "📤 Pushing Node Backend..."
                    docker push ${DOCKERHUB_USERNAME}/cksfinbot-node-backend:latest
                    echo "🧹 Cleaning Node Backend image..."
                    docker rmi ${DOCKERHUB_USERNAME}/cksfinbot-node-backend:latest || true
                    docker image prune -f || true
                """
            }
        }

        stage('Python Backend - Build, Push & Clean') {
            when {
                expression { env.BUILD_PYTHON == 'true' }
            }
            steps {
                sh """
                    echo "🔨 Building Python Backend..."
                    cd ${WORKSPACE}/CKsFinBot/Python-Backend
                    docker build --no-cache --network host -t ${DOCKERHUB_USERNAME}/cksfinbot-python-backend:latest .
                    echo "📤 Pushing Python Backend..."
                    docker push ${DOCKERHUB_USERNAME}/cksfinbot-python-backend:latest
                    echo "🧹 Cleaning Python Backend image..."
                    docker rmi ${DOCKERHUB_USERNAME}/cksfinbot-python-backend:latest || true
                    docker image prune -f || true
                """
            }
        }

        stage('Apply K8s Secrets') {
            steps {
                withCredentials([
                    file(credentialsId: 'mongo-secret', variable: 'MONGO_SECRET'),
                    file(credentialsId: 'node-backend-secret', variable: 'NODE_SECRET'),
                    file(credentialsId: 'python-backend-secret', variable: 'PYTHON_SECRET')
                ]) {
                    sh """
                        kubectl apply -f $MONGO_SECRET
                        kubectl apply -f $NODE_SECRET
                        kubectl apply -f $PYTHON_SECRET
                    """
                }
            }
        }

        stage('Deploy to Kubernetes') {
            steps {
                sh """
                    # Step 1: Create namespace first
                    kubectl apply -f ${K8S_DIR}/namespace.yml

                    # Step 2: Install VPA CRDs if not installed
                    kubectl get crd verticalpodautoscalers.autoscaling.k8s.io > /dev/null 2>&1 || \
                    kubectl apply -f https://raw.githubusercontent.com/kubernetes/autoscaler/master/vertical-pod-autoscaler/deploy/vpa-v1-crd-gen.yaml

                    # Step 3: Apply configmaps
                    kubectl apply -f ${K8S_DIR}/mongo-configmap.yml
                    kubectl apply -f ${K8S_DIR}/mongo-init-configmap.yml
                    kubectl apply -f ${K8S_DIR}/node-backend-configmap.yml
                    kubectl apply -f ${K8S_DIR}/python-backend-configmap.yml
                    kubectl apply -f ${K8S_DIR}/frontend-configmap.yml

                    # Step 4: Apply storage
                    kubectl apply -f ${K8S_DIR}/mongo-pv.yml

                    # Step 5: Apply deployments and services
                    kubectl apply -f ${K8S_DIR}/mongo-statefulset.yml
                    kubectl apply -f ${K8S_DIR}/mongo-service.yml
                    kubectl apply -f ${K8S_DIR}/node-backend-deployment.yml
                    kubectl apply -f ${K8S_DIR}/node-backend-service.yml
                    kubectl apply -f ${K8S_DIR}/python-backend-deployment.yml
                    kubectl apply -f ${K8S_DIR}/python-backend-service.yml
                    kubectl apply -f ${K8S_DIR}/frontend-deployment.yml
                    kubectl apply -f ${K8S_DIR}/frontend-service.yml

                    # Step 6: Apply ingress
                    kubectl apply -f ${K8S_DIR}/ingress-merged.yaml

                    # Step 7: Apply HPA
                    kubectl apply -f ${K8S_DIR}/node-backend-hpa.yml

                    # Step 8: Apply VPA (skip if CRDs not available)
                    kubectl apply -f ${K8S_DIR}/vpa.yml 2>/dev/null || echo "⚠️ VPA skipped - CRDs not ready"
                """
            }
        }

        stage('Rollout Restart') {
            steps {
                script {
                    if (env.BUILD_FRONTEND == 'true') {
                        sh "kubectl rollout restart deployment/finbot-frontend -n finbot"
                        sh "kubectl rollout status deployment/finbot-frontend -n finbot --timeout=120s"
                    }
                    if (env.BUILD_NODE_BACKEND == 'true') {
                        sh "kubectl rollout restart deployment/node-backend -n finbot"
                        sh "kubectl rollout status deployment/node-backend -n finbot --timeout=120s"
                    }
                    if (env.BUILD_PYTHON == 'true') {
                        sh "kubectl rollout restart deployment/python-backend -n finbot"
                        sh "kubectl rollout status deployment/python-backend -n finbot --timeout=120s"
                    }
                    if (env.BUILD_MONGO == 'true') {
                        sh "kubectl rollout restart statefulset/mongo -n finbot"
                        sh "kubectl rollout status statefulset/mongo -n finbot --timeout=120s"
                    }
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                sh """
                    echo "📋 Current pods status:"
                    kubectl get pods -n finbot
                    echo "💾 Docker disk usage after cleanup:"
                    docker system df
                """
            }
        }
    }

    post {
        success {
            echo '✅ Pipeline completed successfully!'
        }
        failure {
            echo '❌ Pipeline failed!'
        }
        always {
            sh "docker logout || true"
        }
    }
}

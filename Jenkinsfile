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
                }
            }
        }

        stage('Docker Login') {
            steps {
                sh "echo ${DOCKERHUB_CREDENTIALS_PSW} | docker login -u ${DOCKERHUB_CREDENTIALS_USR} --password-stdin"
            }
        }

        stage('Build & Push Frontend') {
            when {
                expression { env.BUILD_FRONTEND == 'true' }
            }
            steps {
                sh """
                    cd CKsFinBot/Frontend
                    docker build -t ${DOCKERHUB_USERNAME}/cksfinbot-frontend:latest .
                    docker push ${DOCKERHUB_USERNAME}/cksfinbot-frontend:latest
                """
            }
        }

        stage('Build & Push Node Backend') {
            when {
                expression { env.BUILD_NODE_BACKEND == 'true' }
            }
            steps {
                sh """
                    cd CKsFinBot/Node-Backend
                    docker build -t ${DOCKERHUB_USERNAME}/cksfinbot-node-backend:latest .
                    docker push ${DOCKERHUB_USERNAME}/cksfinbot-node-backend:latest
                """
            }
        }

        stage('Build & Push Python Backend') {
            when {
                expression { env.BUILD_PYTHON == 'true' }
            }
            steps {
                sh """
                    cd CKsFinBot/Python-Backend
                    docker build -t ${DOCKERHUB_USERNAME}/cksfinbot-python-backend:latest .
                    docker push ${DOCKERHUB_USERNAME}/cksfinbot-python-backend:latest
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
                sh "kubectl apply -f ${K8S_DIR}/"
            }
        }

        stage('Rollout Restart') {
            steps {
                script {
                    if (env.BUILD_FRONTEND == 'true') {
                        sh "kubectl rollout restart deployment/finbot-frontend -n finbot"
                    }
                    if (env.BUILD_NODE_BACKEND == 'true') {
                        sh "kubectl rollout restart deployment/node-backend -n finbot"
                    }
                    if (env.BUILD_PYTHON == 'true') {
                        sh "kubectl rollout restart deployment/python-backend -n finbot"
                    }
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                sh "kubectl get pods -n finbot"
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
    }
}

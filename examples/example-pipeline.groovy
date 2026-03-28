// example-pipeline.groovy
// A minimal Jenkins pipeline that targets the Raspberry Pi agent.
// Configure the agent label in Jenkins → Manage Nodes → <node> → Labels.

pipeline {
    agent {
        label 'raspberry'          // matches the label set on the RPi node
    }

    options {
        timeout(time: 15, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timestamps()
    }

    environment {
        // Non-sensitive defaults; override in Jenkins Credentials / parameters
        DEPLOY_ENV = 'production'
    }

    stages {
        stage('System Info') {
            steps {
                sh '''
                    echo "=== Host ==="
                    uname -a
                    echo "=== CPU ==="
                    cat /proc/cpuinfo | grep -E "^(Model|Hardware|Revision)" || true
                    echo "=== Memory ==="
                    free -h
                    echo "=== Disk ==="
                    df -h /
                '''
            }
        }

        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Build') {
            steps {
                echo "Running build on Raspberry Pi agent..."
                sh 'echo "Build step – replace with your actual build command"'
            }
        }

        stage('Test') {
            steps {
                echo "Running tests..."
                sh 'echo "Test step – replace with your actual test command"'
            }
        }

        stage('Deploy') {
            when {
                branch 'main'
            }
            steps {
                echo "Deploying to ${DEPLOY_ENV}..."
                sh 'echo "Deploy step – replace with your actual deploy command"'
            }
        }
    }

    post {
        always {
            echo "Pipeline finished with status: ${currentBuild.currentResult}"
        }
        success {
            echo "Build succeeded!"
        }
        failure {
            echo "Build failed. Check the logs above."
        }
        cleanup {
            cleanWs()
        }
    }
}

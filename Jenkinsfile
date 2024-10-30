pipeline {
    agent any 

     options {
        timeout(time: 10, unit: 'MINUTES')
     }
    environment {
    DOCKERHUB_PAT = credentials('Dockerhub-pat2')
    APP_NAME = "khingarthur/aide-app"
    }
    stages { 
        stage('SCM Checkout') {
            steps{
           git branch: 'main', url: 'https://github.com/khingarthur/aide-app.git'
            }
        }

        stage('Build docker image') {
            steps {  
                sh 'docker build -t $APP_NAME:$BUILD_NUMBER .'
            }
        }

        stage('Trivy Scan (Aqua)') {
            steps {
                sh 'trivy image $APP_NAME:$BUILD_NUMBER'
            }
        }

        stage('login to dockerhub') {
            steps{
              withCredentials([string(credentialsId: "Dockerhub-pat2", variable: "DOCKERHUB_PAT")]) {
            sh "echo $DOCKERHUB_PAT | docker login -u khingarthur --password-stdin"      
                }
            }

        }
        stage('push image') {
            steps{
                sh 'docker push $APP_NAME:$BUILD_NUMBER'
            }
        }

         stage('Trigger ManifestUpdate') {
             steps{
                build job: 'Argocd-aideapp-manifest', parameters: [string(name: 'DOCKERTAG', value: env.BUILD_NUMBER)]     

            } 
           }     
    }
}

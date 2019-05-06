pipeline 
{
    agent any
    
    environment
    {
        deploymentBranch = "ITADMIN-1728"
        imageName = "avides/mysql-s3-backup"
        version = readFile("version.txt").trim()
    }
        
    triggers
    {
        cron('H H(0-5) * * *')
        pollSCM('@hourly')
    }

    options
    {
        buildDiscarder(logRotator(numToKeepStr:'10'))
        disableConcurrentBuilds()
		skipStagesAfterUnstable()
        timeout(time: 1, unit: 'HOURS')
    }

    stages
    {
        stage ('Build image')
        {
            steps
            {
                sh "docker build -t ${imageName}:${version} -t ${imageName}:latest ."
            }
        }
        
        stage ('Push image')
        {
            when { branch "${env.deploymentBranch}" }
        
            steps
            {
                sh "docker push ${imageName}:${version} && docker push ${imageName}:latest"
            }
        }        
    }
}

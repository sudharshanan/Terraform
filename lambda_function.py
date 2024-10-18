import os
import paramiko
import boto3

def lambda_handler(event, context):
    ec2_instance_id = os.getenv('EC2_INSTANCE_ID')
    key_path = "/path/to/your/private-key.pem"  # Ensure Lambda can access this key
    ssh_user = "ec2-user"
    ecr_image_uri = event['detail']['repository-name'] + ":" + event['detail']['image-tag']

    # Get EC2 instance public IP
    ec2 = boto3.client('ec2')
    response = ec2.describe_instances(InstanceIds=[ec2_instance_id])
    public_ip = response['Reservations'][0]['Instances'][0]['PublicIpAddress']

    # SSH into the instance and pull the new image
    try:
        key = paramiko.RSAKey.from_private_key_file(key_path)
        ssh = paramiko.SSHClient()
        ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        ssh.connect(public_ip, username=ssh_user, pkey=key)

        # Pull the latest image and restart the container
        commands = [
            f"docker pull {ecr_image_uri}",
            "docker stop my-app || true",
            f"docker run -d --rm --name my-app {ecr_image_uri}"
        ]

        for command in commands:
            stdin, stdout, stderr = ssh.exec_command(command)
            print(stdout.read().decode())
            print(stderr.read().decode())

        ssh.close()
    except Exception as e:
        print(f"Error: {str(e)}")
        raise

    return {"status": "success"}

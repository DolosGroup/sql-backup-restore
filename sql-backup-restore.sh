#!/bin/bash
# ____        _            ____
#|  _ \  ___ | | ___  ___ / ___|_ __ ___  _   _ _ __
#| | | |/ _ \| |/ _ \/ __| |  _| '__/ _ \| | | | '_ \
#| |_| | (_) | | (_) \__ \ |_| | | | (_) | |_| | |_) |
#|____/ \___/|_|\___/|___/\____|_|  \___/ \__,_| .__/
#SQL Server Database Backup Restore Tool       |_|

#Prereqs: as long as you have awscli, sqlcmd, and working aws creds, you should be all set

# YOU ARE RESPONSIBLE FOR ANY CHARGES ON YOUR AWS ACCOUNT
# The following are created from this script:
#    - RDS Database
#    - RDS Option Group
#    - IAM role
#    - IAM policy
#    - VPC Security Group
# The names for these items are in the variables below.

usage()
{
cat << EOF
usage: $0 options
This script restores a SQL Server database backup to AWS and returns
connection details & a table count
OPTIONS:
   -h      Show this message
   -f      The SQL Server Database backup file (usually .bak)
   -d      Database Name (ex. MYDATBASE)
EOF
}

BASE=sql-restore
S3_BUCKET_NAME=s3-${BASE}-$(openssl rand -base64 10 | tr -d '[:punct:]' | tr -d '[:upper:]') # change if you want a custom bucket
BACKUP_FILE_NAME=""
BACKUP_FILE_DATABASE_NAME=""
RDS_DB_NAME=db-${BASE}-$(openssl rand -base64 10 | tr -d '[:punct:]' | tr -d '[:upper:]')
RDS_SQL_USERNAME=user$(openssl rand -base64 10 | tr -d '[:punct:]' | tr -d '[:upper:]')
RDS_SQL_PASSWORD=pass$(openssl rand -base64 10 | tr -d '[:punct:]' | tr -d '[:upper:]')
RDS_OPTION_GROUP_NAME=option-group-${BASE}
RDS_INSTANCE_CLASS=db.t2.small #change to db.r4.xlarge–16xlarge if using sqlserver-ee
RDS_ENGINE_NAME=sqlserver-ex #SQL SERVER EXPRESS: max 10GB restore (if bigger, use sqlserver-ee)
RDS_ENGINE_VERSION=14.00
RDS_HOSTNAME="" #populated below
IAM_ROLE_NAME="role-${BASE}"
IAM_ROLE_ARN="" #populated below
IAM_POLICY_NAME="policy-${BASE}"
IAM_POLICY_ARN="" #populated below
RDS_DB_HD_SIZE=20 #GB
VPC_SECURITY_GROUP_ID="" #populated below

while getopts "hf:d:" OPTION
do
     case ${OPTION} in
         h)
             usage
             exit 1
             ;;
         f)
             BACKUP_FILE_NAME=${OPTARG}
             ;;
         d)
             BACKUP_FILE_DATABASE_NAME=${OPTARG}
             ;;
         ?)
             usage
             exit
             ;;
     esac
done

#check the required params are supplied
if [[ -z ${BACKUP_FILE_NAME} ]] || [[ -z ${BACKUP_FILE_DATABASE_NAME} ]]; then
    usage
    exit 1
fi

#check if the backup file exists and is not zero bytes
if [[ -f ${BACKUP_FILE_NAME} ]] && [[ -s ${BACKUP_FILE_NAME} ]]; then
    : 
else
    echo "[*] ERROR - File is either empty or doesnt exist"
    exit 1
fi

#make sure AWS CLI is in path:
if ! which aws > /dev/null; then
    echo "[*] ERROR - You must have AWS CLI installed for this to work (EXITING)"
    echo "  Install it from your favorite package manager"
    exit 1
fi
#make sure sqlcmd is in path:
if ! which sqlcmd > /dev/null; then
    echo "[*] ERROR - You must have sqlcmd installed for this to work (EXITING)"
    echo "  Install it from https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools?view=sql-server-2017"
    exit 1
fi

#run basic command to see if awscli is configured properly
if ! aws rds describe-db-instances > /dev/null; then
    echo "[*] ERROR - You must have configured working AWS creds. Run aws configure with your API creds"
    exit 1
fi

echo "[*] Creating S3 Bucket to store database backup: ${S3_BUCKET_NAME}"
aws s3 mb s3://${S3_BUCKET_NAME} > /dev/null 

echo "[*] Uploading backup file (${BACKUP_FILE_NAME}) to S3 bucket (${S3_BUCKET_NAME})"
aws s3 cp ${BACKUP_FILE_NAME} s3://${S3_BUCKET_NAME}

echo "[*] Creating a VPC security group allowing TCP1433 inbound for RDS"
if aws ec2 describe-security-groups --group-names=allow_SQL_in &> /dev/null; then
    echo "[*] allow_SQL_in VPC group already exists, using that one"
    VPC_SECURITY_GROUP_ID=$(aws ec2 describe-security-groups \
        --group-names=allow_SQL_in \
        --query='SecurityGroups[*].GroupId' \
        --output=text)
    sleep 1
else
    VPC_SECURITY_GROUP_ID=$(aws ec2 create-security-group \
        --group-name=allow_SQL_in \
        --description='any outbound, only 1433 inbound' \
        --query="GroupId" \
        --output=text)
    sleep 1
    aws ec2 authorize-security-group-ingress \
        --group-name=allow_SQL_in \
        --ip-permissions IpProtocol=tcp,FromPort=1433,ToPort=1433,IpRanges=[{CidrIp=0.0.0.0/0}] > /dev/null
    sleep 1
fi

echo "[*] Creating the IAM Role & Policy so RDS can access S3"
if aws iam get-role --role-name=${IAM_ROLE_NAME} &> /dev/null; then
    echo "[*] ${IAM_ROLE_NAME} IAM role already exists, using that one"
    IAM_ROLE_ARN=$(aws iam get-role \
        --role-name=${IAM_ROLE_NAME} \
        --query="Role.Arn" \
        --output=text)
    sleep 1
else
    # Create the role to hold the policy
    IAM_ROLE_ARN=$(aws iam create-role \
        --role-name ${IAM_ROLE_NAME} \
        --assume-role-policy-document='{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"rds.amazonaws.com"},"Action":"sts:AssumeRole"}]}' \
        --query='Role.Arn' \
        --output=text)
    sleep 1
    #Create the actual policy that allows talking to S3
    IAM_POLICY_ARN=$(aws iam create-policy \
        --policy-name=${IAM_POLICY_NAME} \
        --policy-document='{"Version":"2012-10-17","Statement":[{"Sid":"VisualEditor0","Effect":"Allow","Action":["s3:GetObject","s3:ListBucket","s3:GetBucketPolicy","s3:GetBucketLocation"],"Resource":"*"}]}' \
        --query='Policy.Arn' \
        --output=text)
    sleep 1
    #attach the policy to the role
    aws iam attach-role-policy \
        --role-name=${IAM_ROLE_NAME} \
        --policy-arn=${IAM_POLICY_ARN} > /dev/null
    sleep 1
fi


echo "[*] Creating an option group (${RDS_OPTION_GROUP_NAME}) to hold the SQLSERVER_BACKUP_RESTORE option for RDS"
if aws rds describe-option-groups --option-group-name=${RDS_OPTION_GROUP_NAME} &> /dev/null; then
    echo "[*] ${RDS_OPTION_GROUP_NAME} group already exists, using that one"
else
    aws rds create-option-group\
        --option-group-name=${RDS_OPTION_GROUP_NAME}\
        --engine-name=${RDS_ENGINE_NAME}\
        --major-engine-version=${RDS_ENGINE_VERSION}\
        --option-group-description="Option Group for restoring SQL Server backup files" > /dev/null
    sleep 1

    echo "[*] Adding the SQLSERVER_BACKUP_RESTORE option to ${RDS_OPTION_GROUP_NAME} group"
    aws rds add-option-to-option-group \
        --option-group-name=${RDS_OPTION_GROUP_NAME} \
        --apply-immediately \
        --options="OptionName=SQLSERVER_BACKUP_RESTORE,OptionSettings=[{Name=IAM_ROLE_ARN,Value=${IAM_ROLE_ARN}}]" > /dev/null
    sleep 1
fi

echo "[*] Creating the RDS SQL Server Database - ${RDS_DB_NAME} ~15mins"
sleep 15 # there is a race condition with some of the options, give it enough time to be ready
aws rds create-db-instance \
    --master-username=${RDS_SQL_USERNAME} \
    --master-user-password=${RDS_SQL_PASSWORD} \
    --engine=${RDS_ENGINE_NAME} \
    --option-group-name=${RDS_OPTION_GROUP_NAME} \
    --allocated-storage=${RDS_DB_HD_SIZE} \
    --publicly-accessible \
    --db-instance-class=${RDS_INSTANCE_CLASS} \
    --db-instance-identifier=${RDS_DB_NAME} \
    --vpc-security-group-ids=${VPC_SECURITY_GROUP_ID} > /dev/null && echo "[*] RDS SQL Server now starting"


while [[ $(aws rds describe-db-instances \
    --db-instance-identifier=${RDS_DB_NAME} \
    --query='DBInstances[*].DBInstanceStatus' \
    --output=text) != 'available' ]]; do
        echo "RDS Still coming up...may take a few minutes"
        #Typically takes ~15mins
        sleep 30
done

echo "[*] SQL Server hostname:"
RDS_HOSTNAME=$( aws rds describe-db-instances \
    --db-instance-identifier=${RDS_DB_NAME} \
    --query='DBInstances[*].Endpoint.Address' \
    --output=text )
echo "Hostname: ${RDS_HOSTNAME}"
echo "Username: ${RDS_SQL_USERNAME}"
echo "Password: ${RDS_SQL_PASSWORD}"

echo "[*] Restoring the SQL server database from S3"
sqlcmd -S ${RDS_HOSTNAME} -U ${RDS_SQL_USERNAME} -P ${RDS_SQL_PASSWORD} -Q "exec msdb.dbo.rds_restore_database @restore_db_name='${BACKUP_FILE_DATABASE_NAME}', @s3_arn_to_restore_from='arn:aws:s3:::${S3_BUCKET_NAME}/$(basename ${BACKUP_FILE_NAME})';" > /dev/null

while ! sqlcmd -S ${RDS_HOSTNAME} -U ${RDS_SQL_USERNAME} -P ${RDS_SQL_PASSWORD} -Q "exec msdb.dbo.rds_task_status @db_name='${BACKUP_FILE_DATABASE_NAME}';" | grep 'SUCCESS'; do
    echo "[*] still restoring the DB"
    sleep 10
done

echo "[*] Row count for all tables in the database"
sqlcmd -S ${RDS_HOSTNAME} -U ${RDS_SQL_USERNAME} -P ${RDS_SQL_PASSWORD} -Q "use ${BACKUP_FILE_DATABASE_NAME}; SELECT object_name(id), rows FROM sysindexes WHERE indid IN (0, 1) ORDER by rows"
echo "[*] Run whatever SQL queries you want with:"
echo sqlcmd -S ${RDS_HOSTNAME} -U ${RDS_SQL_USERNAME} -P ${RDS_SQL_PASSWORD} 

#TO REMOVE THE RDS & S3:
########################DELETE RDS SERVERS####################
# RDS_SERVERS=$(aws rds describe-db-instances --query='DBInstances[*].DBInstanceIdentifier' --output=text)
# for i in ${RDS_SERVERS}; do
#     if echo ${i} | grep 'db-sql-restore'; then
#         read -p "--------Delete RDS ${i} ? y/n: " reply
#         [[ $reply == 'y' ]] && aws rds delete-db-instance --db-instance-identifier=${i} --skip-final-snapshot
#     fi
# done


# ########################DELETE BUCKETS########################
# BUCKETS=$(aws s3api list-buckets --query='Buckets[*].Name' --output=text)
# for i in ${BUCKETS}; do
#     if echo $i | grep 's3-sql-restore-' ; then
#         read -p "--------Delete S3 ${i} ? y/n: " reply
#         [[ $reply == 'y' ]] && aws s3 rb s3://$i --force
#     fi
# done
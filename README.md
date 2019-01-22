# sql-backup-restore
This tool takes a SQL Server database backup file and name and restores it to AWS. It returns a table count as well as connection details.

## Requirements:
- awscli in PATH (`which aws`)
  - available from pip (`pip install awscli`)
- AWS API creds (`aws configure`)
- sqlcmd in PATH (`which sqlcmd`)
  - available from https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools?view=sql-server-2017

## Example:
No arguments:
```
$ ./sql-backup-restore.sh
usage: ./sql-backup-restore.sh options
This script restores a SQL Server database backup to AWS and returns
connection details & a table count

OPTIONS:
   -h      Show this message
   -f      The SQL Server Database backup file (usually .bak)
   -d      Database Name (ex. MYDATBASE)
```

Example usage:
```
$ ./sql-backup-restore.sh -f ~/JulyDatabaseBackup.bak -d THISISMYDATABASENAME
[*] Creating S3 Bucket to store database backup: s3-sql-restore-wi41zjcsdg
[*] Uploading backup file (/root/JulyDatabaseBackup.bak) to S3 bucket (s3-sql-restore-wi41zjcsdg)
upload: ../JulyDatabaseBackup.bak to s3://s3-sql-restore-wi41zjcsdg/JulyDatabaseBackup.bak
[*] Creating a VPC security group allowing TCP1433 inbound for RDS
[*] Creating the IAM Role & Policy so RDS can access S3
[*] Creating an option group (option-group-sql-restore) to hold the SQLSERVER_BACKUP_RESTORE option for RDS
[*] Adding the SQLSERVER_BACKUP_RESTORE option to option-group-sql-restore group
Username: user34wkeceq
Password: pass9zoacs5
[*] Creating the RDS SQL Server Database - db-sql-restore-rwkmm7hog ~15mins
[*] RDS SQL Server now starting
RDS Still coming up...may take a few minutes
<SNIP>
RDS Still coming up...may take a few minutes
RDS Still coming up...may take a few minutes
[*] SQL Server hostname:
Hostname: db-sql-restore-rwkmm7hog.cicdy9uy2.us-east-1.rds.amazonaws.com
Username: user34wkeceq
Password: pass9zoacs5
[*] Restoring the SQL server database from S3
[*] still restoring the DB
<SNIP>
[*] still restoring the DB
          1 RESTORE_DB                                         THISISMYDATABASENAME                                                    [2019-01-18 1 2019-01-18 16:42:22.087 2019-01-18 16:41:15.730 arn:aws:s3:::s3-sql-restore-wi41zjcsdg/JulyDatabaseBackup.bak                                                                                                                                                                                                                                                                                                      0 NULL
[*] Row count for all tables in the database
Changed database context to 'THISISMYDATABASENAME'.
                         rows
------------------------ -----------
sysclones                          0
sysseobjvalues   
<SNIP>                          1220
sysschobjs                      2428

(94 rows affected)
[*] Run whatever SQL queries you want with:
sqlcmd -S db-sql-restore-rwkmm7hog.cicdy9uy2.us-east-1.rds.amazonaws.com -U user34wkeceq -P pass9zoacs5
```

## Caveats:
The script is currently written to save you some money by using SQL Server Express which limits the database restore to 10GB. If your restore is larger, change the RDS_INSTANCE_CLASS variable to sqlserver-ee (Enterprise Edition) and the HD size accordingly. SQL Server Enterprise Edition supports restores up to 500+ PB.

Also, you need to know the database name within the backup file (AWS requires this). Fortunately, in the vast majority of cases its the same as the name of the backup file itself. In the cases where it's not you can easily look at the first couple kilobytes in a hex editor (`xxd name_of_backup.bak | less `) and retrieve it.
# Installing sql-backup-restore
All the tool needs is `aws` and `sqlcmd` in PATH along with working AWS API credentials (procured from your IAM console).

## AWS
Install aws using pip (2 or 3 is ok): `pip install awscli`

Configure your credentials and region: `aws configure`

## SQLCMD
Install sqlcmd by following the steps here: 
 - LINUX: https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools?view=sql-server-2017#offline-installation
 - MACOS: https://docs.microsoft.com/en-us/sql/linux/sql-server-linux-setup-tools?view=sql-server-2017#macos

Once those steps are complete, you should have `aws` and `sqlcmd` in your PATH (`echo $PATH`). 

## NOTE:
A couple of redhat based systems don't symlink the sqlcmd binary to PATH. You can do it yourself by running `sudo ln -s /opt/mssql-tools/bin/sqlcmd /usr/local/bin/`
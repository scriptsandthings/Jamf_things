### Updating Jamf Pro 10 for primary + child/forwarding configuration

1. Snapshot/Backup all servers
2. Create backup of Jamf SQL Database
3. Copy SQL DB backup to a seperate network/backup share
4. Stop tomcat on child/external server
5. Stop tomcat on primary server
6. Install Jamf update on primary server
7. Reboot primary server
8. Verify update successful
9. Complete update on child/forwarding server
10. Reboot child/forwarding server
11. Verify update successful
12. Remove snapshots and DB backup

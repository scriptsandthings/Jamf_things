### Updating Jamf Pro 10 for primary + child/forwarding configuration

1. Snapshot/Backup all servers
2. Verify snapshots
3. Create backup of Jamf SQL Database from parent server
4. Copy SQL DB backup to a seperate network/backup share
5. Stop tomcat on child/external server
6. Stop tomcat on primary server
7. Install Jamf update on primary server
8. Reboot primary server
9. Verify update successful
10. Complete update on child/forwarding server
11. Reboot child/forwarding server
12. Verify update successful
13. Remove snapshots and DB backup

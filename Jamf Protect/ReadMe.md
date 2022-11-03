Here's some Jamf Protect/Universal Syslog predicates

log show --style syslog --predicate 'process == "corp.sap.privileges.helper" && eventMessage CONTAINS
"SAPCorp" && eventMessage CONTAINS "reason"'

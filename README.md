# 🧩 Active Directory Migration Script v2.0

## 📘 Overview
This PowerShell script automates **the export, import, and synchronization of Active Directory objects** (users, groups, memberships, and attributes) during an **AD-to-AD or hybrid-to-cloud migration**.  
It also supports **Microsoft 365 integration** via Graph API for Immutable ID management, user restoration, and UPN re-assignment.

It includes **logging, user feedback, and error handling** to simplify and secure each migration step.

---

## ⚠️ Important Migration Warning (AD ➜ Cloud ➜ AD)

This script supports **multi-stage migrations** between on-premises Active Directory and Azure AD (full cloud).  
However, special attention is required when **moving users from AD → Cloud (Azure AD)** and then **restoring them back to AD** after a “bounce” or rebind operation.

### 🔸 Context
- When users are **synchronized from on-prem AD to Azure AD**, each object gets a unique **ImmutableId**.
- During a **full cloud migration**, users may be **converted to cloud-only accounts** (ImmutableId removed).
- If these same users are **later restored in Azure AD (via Microsoft Graph)** and **reconnected to a new on-prem AD**, attribute mismatches can cause sync issues, duplicate accounts, or authentication errors.

### 🔸 Recommendation
Before performing a **reverse migration (Cloud ➜ AD)** or a **domain suffix change**:
1. **Always clear the ImmutableId** using the function  
   ```powershell
   Clear-O365ImmutableIdInOU -OUPath "OU=YourOU,DC=domain,DC=local"
   ```
   This ensures Azure AD will re-link users cleanly during the next sync.

2. **Apply the `User_NoSync` marker** on local users before resynchronization:  
   ```powershell
   Set-AdminDescriptionToNoSync -OUPath "OU=YourOU,DC=domain,DC=local"
   ```

3. After confirming the environment is ready, **remove** the `User_NoSync` flag using:
   ```powershell
   Clear-AdminDescriptionInOU -OUPath "OU=YourOU,DC=domain,DC=local"
   ```

4. **Never reuse an existing ImmutableId** between two directories.  
   Always let Azure AD Connect reassign it automatically upon re-sync.

### 🔸 Typical “Bounce” Scenario Supported by the Script
1. **Export** users and groups from source AD.  
2. **Import** them into a target AD or cloud staging OU.  
3. **Clear ImmutableId** to “unlink” cloud objects.  
4. **Disable** source accounts to prevent duplicates.  
5. **Restore** users in Azure AD via Graph (function `Enable-AccountsFromOU`) and **update their UPNs**.  
6. Optionally, re-sync them to a new on-prem domain.

💡 *This process is safe only if ImmutableId cleanup and adminDescription tagging are properly performed before and after migration.*

---

## ⚙️ Main Features

### 🔹 Export (Source AD)
| Function | Description |
|-----------|--------------|
| `Export-ADUsers` | Exports users and their full attributes (UPN, ProxyAddresses, Department, Manager, etc.) from a specific OU. |
| `Export-ADGroups` | Exports security groups and all their members (including nested). |
| `Export-UserGroupMemberships` | Exports direct group memberships of users in a specific OU. |

---

### 🔹 Import (Target AD)
| Function | Description |
|-----------|--------------|
| `Import-ADUsers` | Recreates users in the target OU using the exported CSV file (with automatic UPN generation and attribute population). |
| `Import-ADGroups` | Creates or updates security groups, then reassigns their members. |
| `Import-UserGroupMemberships` | Re-adds users to groups based on exported membership data. |

---

### 🔹 Attribute Management (Target AD)
| Function | Description |
|-----------|--------------|
| `Update-ADProxyAddressesFromCsv` | Reapplies ProxyAddresses to users from the export file. |
| `Set-ADUserManagerFromCsv` | Restores each user’s Manager attribute. |
| `Update-ADSalesForceProfileIDFromCsv` | Reimports SalesforceProfileID custom attributes. |
| `Update-UPNSuffixInOU` | Rewrites all UPN suffixes in a given OU. |
| `Set-AdminDescriptionToNoSync` | Adds `User_NoSync` to prevent Azure AD sync. |
| `Clear-AdminDescriptionInOU` | Removes `User_NoSync` from users. |

---

### 🔹 Microsoft 365 Integration
| Function | Description |
|-----------|--------------|
| `Clear-O365ImmutableIdInOU` | Connects to Microsoft Graph and clears the `ImmutableId` for all users in the OU. |
| `Enable-AccountsFromOU` | Restores deleted users in Microsoft 365 and updates their UPNs. |

---

### 🔹 Other Administrative Actions
| Function | Description |
|-----------|--------------|
| `Disable-ADAccountsFromOU` | Disables all active AD accounts in a given OU. |
| `Clear-O365ImmutableIdInOU` | Generates a report of all Immutable ID removals. |

---

## 🧰 Requirements

### 🧩 PowerShell Modules
```powershell
Install-Module ActiveDirectory
Install-Module Microsoft.Graph
```

### 🧩 Permissions
| Environment | Required Role |
|--------------|----------------|
| On-prem Active Directory | Domain Admin or delegated OU admin |
| Microsoft 365 / Azure AD | User Administrator or higher |

### 🧩 File System
Ensure this path exists (or adjust it in the script):
```
C:\Temp\
```

---

## 🧾 Logging
Logs are written to:
```
C:\Temp\ADMigration.log
```

Levels: `[INFO]`, `[SUCCESS]`, `[WARNING]`, `[ERROR]`

---

## 💻 Interactive Menu
Integrated console interface:
```
1.  Export users
2.  Export security groups
3.  Export memberships
4.  Import users
5.  Import groups
6.  Import memberships
7.  Update ProxyAddresses
8.  Update Managers
9.  Update Salesforce IDs
10. Update UPN Suffix
11. Clear "User_NoSync"
12. Add "User_NoSync"
13. Remove Immutable ID (Graph)
14. Disable AD accounts
15. Restore O365 users / UPNs
16. Exit
```

---

## 📊 Output Files
| File | Description |
|-------|--------------|
| `AD_Users.csv` | User export. |
| `AD_Groups.csv` | Security group export. |
| `User_Group_Memberships.csv` | Group memberships. |
| `ImmutableId_Report.csv` | Immutable ID cleanup report. |
| `AdminDescription_Update_Report.csv` | “User_NoSync” attribute update log. |

---

## 🧱 Best Practices
- Always **test exports before imports**.
- Use a **dedicated test OU**.
- Run **as Administrator**.
- **Verify Microsoft Graph connection** before M365 actions.
- **Check `ADMigration.log`** after each step.
- During hybrid transitions, **control synchronization** using `User_NoSync` and `ImmutableId` functions.



---

## 📄 License
This script is provided “as is” without warranty.  
You are free to modify and adapt it for your organization’s migration processes.

---

# ✅ Password Placeholders Restored

All values files now use placeholders instead of actual passwords.

## Files Updated (6 files)

- ✅ `values/keystone-values.yaml`
- ✅ `values/glance-values.yaml`
- ✅ `values/placement-values.yaml`
- ✅ `values/neutron-values-controlplane.yaml`
- ✅ `values/nova-values.yaml`
- ✅ `values/horizon-values.yaml`

## Placeholders Used

- `PASSWORD_PLACEHOLDER` → MariaDB root password
- `RABBITMQ_ADMIN_USER` → RabbitMQ admin username
- `RABBITMQ_ADMIN_PASSWORD` → RabbitMQ admin password

## Safe to Push to GitHub ✅

All sensitive credentials have been removed. You can now safely:

\`\`\`bash
git add .
git commit -m "Add OpenStack Helm values files with placeholders"
git push
\`\`\`

## To Restore Passwords Locally

After pulling from GitHub, run:

\`\`\`bash
./update-passwords-manual.sh
\`\`\`

See: `values/README-passwords.md` for details.

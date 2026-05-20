# Derived SQL Server image that adds mssql-server-fts on top of the official
# mcr.microsoft.com/mssql/server:2022-latest. Required by Business Central
# when creating new per-company tables (full-text indexes) — without it,
# Company.Insert / Database.CopyCompany fail with:
#
#   Text optimized index cannot be created/queried because the SQL Server
#   Full-Text Search component is not installed.
#
# Source-of-truth in this repo: scripts/bc-linux-overrides/sql-fts.Dockerfile
# Copied into bc-linux/ at runtime by scripts/seed-company.sh (the bc-linux/
# checkout is gitignored and re-cloned from upstream on fresh clones, so
# we keep the canonical copy here).
#
# Per ADR 0013. Once StefanMaron/MsDyn365Bc.On.Linux upstreams FTS support
# (no issue filed yet), this file and the override below can be deleted.
FROM mcr.microsoft.com/mssql/server:2022-latest

USER root
RUN printf 'deb [arch=amd64,arm64,armhf] https://packages.microsoft.com/ubuntu/22.04/mssql-server-2022 jammy main\n' \
        > /etc/apt/sources.list.d/mssql-server-2022.list \
    && apt-get update \
    && ACCEPT_EULA=Y apt-get install -y --no-install-recommends mssql-server-fts \
    && rm -rf /var/lib/apt/lists/* \
    # The mssql-server-fts postinst script triggers a SQL setup pass that
    # populates /var/opt/mssql/{data,log,.system,mssql.conf}. Leaving those
    # in the image conflicts with docker-compose's tmpfs mount on
    # /var/opt/mssql/data at runtime (tmpfs takes mssql:root → mssql can't
    # write). Strip the pre-init state so the image looks like the upstream
    # mcr.microsoft.com/mssql/server:2022-latest's empty /var/opt/mssql/.
    && rm -rf /var/opt/mssql/* /var/opt/mssql/.system \
    && chown root:mssql /var/opt/mssql \
    && chmod 770 /var/opt/mssql
USER mssql

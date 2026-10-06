# Network Watcher y restricciones del runtime

No uses Network Watcher desde el agente. Aunque la identidad tiene acceso al recurso regional, el clasificador del runner no admite el verbo compuesto `test-ip-flow`.

Tampoco uses VM Run Command, `curl` ni `az rest`. Las VM generan sondas TCP/8080 continuamente y la verificación end-to-end se realiza con `AZFWNetworkRule` mediante `QueryLogAnalyticsByWorkspaceId`.

Para la configuración usa únicamente los comandos `show` y `update` documentados en la skill `network-triage` y en `runtime-command-constraints.md`.

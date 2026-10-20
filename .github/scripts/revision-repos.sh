#!/usr/bin/env bash
# Revisa los repos públicos propios (sin forks ni archivados) y mantiene un solo
# issue abierto con los que no tienen licencia, descripción o topics. Si todo
# está en orden, cierra ese issue.
#
# Variables: OWNER (dueño de los repos), IGNORAR (repos a omitir, separados por
# espacio), ETIQUETA y TITULO del issue. Con DRY_RUN=1 solo imprime el reporte.
set -euo pipefail

OWNER="${OWNER:?falta OWNER}"
IGNORAR="${IGNORAR:-}"
ETIQUETA="${ETIQUETA:-revision-repos}"
TITULO="${TITULO:-Revisión semanal: repos públicos incompletos}"

filas=$(gh repo list "$OWNER" --visibility public --source --no-archived --limit 200 \
    --json name,description,licenseInfo,repositoryTopics |
  jq -r --arg owner "$OWNER" --arg ignorar " $IGNORAR " '
    map(select(.name as $n | ($ignorar | contains(" " + $n + " ")) | not))
    | map({name, falta: [
        (if .licenseInfo == null then "licencia" else empty end),
        (if ((.description // "") | length) == 0 then "descripción" else empty end),
        (if ((.repositoryTopics // []) | length) == 0 then "topics" else empty end)
      ]})
    | map(select(.falta | length > 0))
    | sort_by(.name | ascii_downcase)
    | .[]
    | "| [\(.name)](https://github.com/\($owner)/\(.name)) | \(.falta | join(", ")) |"')

resumen() { if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then printf '%s\n' "$1" >> "$GITHUB_STEP_SUMMARY"; fi; }
gh_escribe() { if [ "${DRY_RUN:-}" = 1 ]; then echo "[dry-run] gh $*"; else gh "$@"; fi; }

if [ "${DRY_RUN:-}" != 1 ]; then
  gh label create "$ETIQUETA" --color BFD4F2 --description "Revisión semanal de repos públicos" --force >/dev/null
fi
abierto=$(gh issue list --label "$ETIQUETA" --state open --json number --jq '.[0].number // empty' 2>/dev/null || true)

if [ -z "$filas" ]; then
  echo "Todos los repos públicos tienen licencia, descripción y topics."
  resumen "Todos los repos públicos tienen licencia, descripción y topics."
  if [ -n "$abierto" ]; then
    gh_escribe issue close "$abierto" --comment "Todo en orden: todos los repos públicos tienen licencia, descripción y topics."
  fi
  exit 0
fi

cuerpo="Repos públicos propios (sin forks ni archivados) a los que les falta algo. Lo actualiza cada lunes \`.github/workflows/revision-repos.yml\`.

| Repo | Falta |
| --- | --- |
$filas

Para pulir uno, pídele a tu agente que use el skill \`pulir-repo\` en ese repo. Este issue se cierra solo cuando todo queda en orden."

printf '%s\n' "$cuerpo"
resumen "$cuerpo"
if [ -n "$abierto" ]; then
  gh_escribe issue edit "$abierto" --body "$cuerpo"
else
  gh_escribe issue create --title "$TITULO" --label "$ETIQUETA" --body "$cuerpo"
fi

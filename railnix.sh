#!/usr/bin/env bash
set -euo pipefail
export RAILWAY_NO_TELEMETRY=1

generateTerraformConfig() {
  echo "[railnix] generate terraform config..."
  nix eval .#lib.generateTerraformConfig --apply "f: f {}" --json | jq -S . > railnix.tf.json
}

init() {
  generateTerraformConfig
  echo "[railnix] initialize terraform..."
  tofu init
}

plan() {
  generateTerraformConfig
  echo "[railnix] preview terraform plan..."
  tofu init && RAILWAY_TOKEN=$RAILWAY_API_TOKEN tofu plan
}

provision() {
  generateTerraformConfig
  echo "[railnix] provision infrastructure..."
  tofu init && RAILWAY_TOKEN=$RAILWAY_API_TOKEN tofu apply -auto-approve
}

deploy() {
  local project_name project_id environment plan services message
  project_name=$(tofu output -raw project_name)
  project_id=$(tofu output -raw project_id)
  environment=$1
  plan=$(nix eval .#lib.generateDeploymentPlan --apply "f: f \"$environment\"" --json)
  services=$(echo "$plan" | jq -r 'keys[]')
  message=${2:-""}
  local message_flag=()
  if [[ -n "$message" ]]; then
    message_flag=(-m "$message")
  fi
  echo "[railnix] deploy '$project_name($environment)'..."
  for service in $services; do
    config=$(echo "$plan" | jq -c ".\"$service\".config")
    echo "[railnix] generate railway.json for '$service'..."
    echo "$config" | jq . > railway.json
    echo "[railnix] deploy '$service'..."
    railway up --ci --project "$project_id" --environment "$environment" --service "$service" "${message_flag[@]}"
  done
  echo "[railnix] done"
}

cleanup() {
  rm -f railnix.tf.json
  rm -f railway.json
}

main() {
  local cmd
  if [ $# -eq 0 ]; then
    echo "Usage: railnix {init|plan|up <environment> [-m <message>]}"
    exit 0
  fi            
  cmd=''${1:-}
  shift

  case "$cmd" in
    init)
      init
      cleanup
      ;;
    plan)
      plan
      cleanup
      ;;
    up)
      local environment
      environment=''${1:-}
      if [ -z "$environment" ]; then
        echo "[railnix] 'railnix up' requires an environment name."
        echo "Usage: railnix up <environment>"
        exit 1
      fi
      provision
      deploy "$environment"
      cleanup
      ;;
    *)
      echo "Usage: railnix {init|plan|up <environment> [-m <message>]}"
      exit 1
      ;;
  esac
}

main "$@"

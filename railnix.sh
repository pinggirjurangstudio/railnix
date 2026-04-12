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
  local project_name project_id environment plan services
  project_name=$(tofu output -raw project_name)
  project_id=$(tofu output -raw project_id)
  environment=$1
  plan=$(nix eval .#lib.generateDeploymentPlan --apply "f: f \"$environment\"" --json)
  services=$(echo "$plan" | jq -r 'keys[]')
  echo "[railnix] deploy '$project_name($environment)'..."
  for service in $services; do
    config=$(echo "$plan" | jq -c ".\"$service\".config")
    echo "[railnix] generate railway.json for '$service'..."
    echo "$config" | jq . > railway.json
    echo "[railnix] deploy '$service'..."
    railway up --json --ci --project "$project_id" --environment "$environment" --service "$service"
  done
  echo "[railnix] done"
}

main() {
  local cmd
  if [ $# -eq 0 ]; then
    echo "Usage: railnix {init|plan|up <environment>}"
    exit 0
  fi            
  cmd=''${1:-}
  shift

  case "$cmd" in
    init)
      init
      ;;
    plan)
      plan
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
      ;;
    *)
      echo "Usage: railnix {init|plan|up <environment>}"
      exit 1
      ;;
  esac
}

main "$@"

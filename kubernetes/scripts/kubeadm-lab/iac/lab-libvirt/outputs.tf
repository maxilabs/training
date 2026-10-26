# Uitvoer na 'terraform apply'. Bekijken: terraform output  (of: terraform output -raw lab_env)

output "nodes" {
  description = "Naam en IP per VM."
  value       = { for k, v in var.nodes : k => v.ip }
}

# Een env-bestand in het formaat van lab.env, zodat de bestaande scripts (prep-nodes.sh, cp-init.sh,
# worker-join.sh) dit tweede cluster kunnen inrichten. De workflow doet:
#   terraform output -raw lab_env > "$RUNNER_TEMP/lab-tf.env"
#   LAB_ENV="$RUNNER_TEMP/lab-tf.env" ./prep-nodes.sh  (enz.)
# Zo komen de nodes maar op één plek vandaan (variables.tf) en kunnen script en Terraform niet uit elkaar lopen.
output "lab_env" {
  description = "Overschrijft NODES en CP_NODE uit lab.env voor het Terraform-cluster."
  value       = <<-EOT
    # gegenereerd door iac/lab-libvirt (terraform output -raw lab_env)
    NODES=(
    %{for k, v in var.nodes~}
      "${k} ${v.ip} ${v.mac} ${v.vcpu} ${v.memory}"
    %{endfor~}
    )
    CP_NODE="${var.control_plane}"
  EOT
}

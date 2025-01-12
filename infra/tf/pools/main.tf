terraform {
	required_providers {
		linode = {
			source = "linode/linode"
			version = "1.29.2"
		}
	}
}

module "secrets" {
	source = "../modules/secrets"

	keys = [
		"linode/terraform/token",
		"ssh/salt_minion/private_key_openssh",
	]
}


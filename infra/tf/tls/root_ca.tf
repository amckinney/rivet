# for creating locally signed certs
resource "tls_private_key" "root_ca" {
  algorithm = "RSA"
}

# create self-signed root certificate, which acts as local CA 
resource "tls_self_signed_cert" "root_ca" {
	key_algorithm   = "RSA"
  	private_key_pem = tls_private_key.root_ca.private_key_pem
  	is_ca_certificate = true

  	subject {
    	common_name  = ""
    	organization = "Rivet Gaming, LLC"
  	}

	validity_period_hours = 8760 # 1 year

	allowed_uses = [
		"key_encipherment",
    	"digital_signature",
    	"cert_signing",
    	"crl_signing"
  	]
}

resource "kubernetes_secret" "ingress_tls_ca_cert_locally_signed" {
	metadata {
		name = "ingress-tls-ca-cert-locally-signed"
		namespace = "traefik-tunnel"
	}

	data = {
		"tls.ca" = tls_self_signed_cert.root_ca.cert_pem
	}
}


locals {
	redis_k8s = var.redis_provider == "kubernetes"
	service_redis = lookup(var.services, "redis", {
		count = 3
		resources = {
			cpu = 50
			cpu_cores = 0
			memory = 200
		}
	})

	redis_svcs = local.redis_k8s ? {
		for k, v in var.redis_dbs:
		k => {
			persistent = v.persistent
			password = module.redis_secrets[0].values["redis/${k}/password"]
		}
		if local.redis_k8s
	} : {}
}

module "redis_secrets" {
	count = local.redis_k8s ? 1 : 0

	source = "../modules/secrets"

	keys = [
		for k, v in var.redis_dbs: "redis/${k}/password"
	]
}

resource "kubernetes_namespace" "redis" {
	depends_on = [ helm_release.prometheus ]
	for_each = var.redis_dbs

	metadata {
		name = "redis-${each.key}"
	}
}

resource "helm_release" "redis" {
	depends_on = [helm_release.prometheus]
	for_each = local.redis_svcs

	name = "redis"
	namespace = kubernetes_namespace.redis[each.key].metadata.0.name
	chart = "../../helm/redis-cluster"
	# repository = "https://charts.bitnami.com/bitnami"
	# chart = "redis-cluster"
	# version = "9.0.6"
	values = [yamlencode({
		password = each.value.password
		global = {
			storageClass = var.k8s_storage_class
		}
		redis = {
			# Use allkeys-lru instead of volatile-lru because we don't want the cache nodes to crash
			extraEnvVars = [
				{ name = "REDIS_MAXMEMORY_POLICY", value = each.value.persistent ? "noeviction" : "allkeys-lru" }
			]
		}
		# Create minimal cluster
		cluster = {
			nodes = local.service_redis.count + var.redis_replicas * local.service_redis.count
			replicas = var.redis_replicas
		}
		master = {
			resources = {
				limits = {
					memory = "${local.service_redis.resources.memory}Mi"
					cpu = (
						local.service_redis.resources.cpu_cores > 0 ?
						"${local.service_redis.resources.cpu_cores * 1000}m"
						: "${local.service_redis.resources.cpu}m"
					)
				}
			}
		}
		auth = {
			enable = true
		}
		tls = {
			enabled = true
			authClients = false
			autoGenerated = true
		}
		persistence = {
			enabled = each.value.persistent
		}
		metrics = {
			enabled = true
			serviceMonitor = {
				enabled = true
				namespace = kubernetes_namespace.redis[each.key].metadata.0.name
			}
			extraArgs = each.key == "chirp" ? {
				"check-streams" = "'{topic:*}:topic'"
			} : {}

			# TODO:
			# prometheusRule = {
			# 	enabled = true
			# 	namespace = kubernetes_namespace.redis[each.key].metadata.0.name
			# }
		}
	})]
}

data "kubernetes_secret" "redis_ca" {
	for_each = var.redis_dbs

	depends_on = [helm_release.redis]

	metadata {
		name = "redis-redis-cluster-crt"
		namespace = kubernetes_namespace.redis[each.key].metadata.0.name
	}
}

resource "kubernetes_config_map" "redis_ca" {
	for_each = merge([
		for ns in ["rivet-service", "bolt"]: {
			for k, v in var.redis_dbs:
				"${k}-${ns}" => {
				db = k
				namespace = ns
			}
		}
	]...)

	metadata {
		name = "redis-${each.value.db}-ca"
		namespace = each.value.namespace
	}

	data = {
		"ca.crt" = data.kubernetes_secret.redis_ca[each.value.db].data["ca.crt"]
	}
}


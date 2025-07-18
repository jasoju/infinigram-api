/**
 * This is a template that's compiled down to a definition of the
 * infrastructural resources required for running your application.
 *
 * For more information on the JSONNET language, see:
 * https://jsonnet.org/learning/getting_started.html
 */

// This file is generated once at template creation time and unlikely to change
// from that point forward.
local config = import '../skiff.json';
local util = import './util.libsonnet';

function(
    apiImage, proxyImage, workerImage, cause, sha, env='staging', branch='', repo='',
    buildId=''
)
    // Produce a list of hostnames served by your application.
    // See: https://skiff.allenai.org/domains.html.
    local domains =
        util.getHosts(env, config, '.apps.allenai.org') +
        util.getHosts(env, config, '.allen.ai') +
        if env == 'prod' && 'customDomains' in config then
            config.customDomains else
        [];

    local grouped = util.groupHosts(
        domains,
        ['.allenai.org', '.allen.ai', '.semanticscholar.org' ]
    );
    local canonical = grouped[0];
    local extra = grouped[1];

    // We provision 3 ingresses so that Skiff Login works with each TLD. We
    // only support 3 TLS for authentication purposes.
    local allenAIHosts = canonical['.allen.ai'];
    local scholarHosts = canonical['.semanticscholar.org'];

    // The allenai.org TLD inherits everything else.
    local hosts = canonical['.allenai.org'] + extra;

    // In production you run should run two or more replicas of your
    // application, so that if one instance goes down or is busy (e.g., during
    // a deployment), users can still use the remaining replicas of your
    // application.
    //
    // However, if you use GPUs, which are expensive, consider setting the prod
    // replica count to 1 as a trade-off between availability and costs.
    //
    // In all other environments (e.g., adhocs) we run a single instance to
    // save money.
    local numReplicas = if env == 'prod' then config.replicas.prod else 1;

    // Each app gets it's own namespace.
    local namespaceName = config.appName;

    // Since we deploy resources for different environments in the same namespace,
    // we need to give things a fully qualified name that includes the environment
    // as to avoid unintentional collission / redefinition.
    local fullyQualifiedName = config.appName + '-' + env;

    // Every resource is tagged with the same set of labels. These labels serve the
    // following purposes:
    //  - They make it easier to query the resources, i.e.
    //      kubectl get pod -l app=my-app,env=staging
    //  - The service definition uses them to find the pods it directs traffic to.
    local namespaceLabels = {
        app: config.appName,
        contact: config.contact,
        team: config.team
    };

    local labels = namespaceLabels + {
        env: env
    };

    local selectorLabels = {
        app: config.appName,
        env: env
    };

    // By default multiple instances of your application could get scheduled
    // to the same node. This means if that node goes down your application
    // does too. We use the label below to avoid that.
    local antiAffinityLabels = {
        onlyOneOfPerNode: config.appName + '-' + env
    };
    local podLabels = labels + antiAffinityLabels;

    // Annotations carry additional information about your deployment that
    // we use for auditing, debugging and administrative purposes
    local annotations = {
        "apps.allenai.org/sha": sha,
        "apps.allenai.org/branch": branch,
        "apps.allenai.org/repo": repo,
        "apps.allenai.org/build": buildId
    };

    // Running on a GPU requires a special limit on the container, and a
    // specific nodeSelector.
    local gpuInConfig = std.count(std.objectFields(config), "gpu") > 0;

    // determine number of gpus
    local gpuLimits = if gpuInConfig then
        if config.gpu == "a100-40gbx2" then
            { 'nvidia.com/gpu': 2 }
        else if config.gpu == "t4x4" then
            { 'nvidia.com/gpu': 4 }
        else
            { 'nvidia.com/gpu': 1 }
    else {};

    local nodeSelector = if gpuInConfig then
        if config.gpu == "p100" then
            { 'cloud.google.com/gke-accelerator': 'nvidia-tesla-p100' }
        else if config.gpu == "t4" || config.gpu == "t4x4" then
            { 'cloud.google.com/gke-accelerator': 'nvidia-tesla-t4' }
        else if config.gpu == "a100-40gb" || config.gpu == "a100-40gbx2" then
            { 'cloud.google.com/gke-accelerator': 'nvidia-tesla-a100' }
        else
            error "invalid GPU specification; expected 'p100', 't4', 't4x4', 'a100-40gb', or 'a100-40gbx2' but got: " + config.gpu
    else
         { };

    // The port the NGINX proxy is bound to.
    local proxyPort = 8080;

    // The port the API (Python Flask application) is bound to.
    local apiPort = 8000;

    // This is used to verify that the proxy (and thereby the UI portion of the
    // application) is healthy. If this fails the application won't receive traffic,
    // and may be restarted.
    local proxyHealthCheck = {
        port: proxyPort,
        scheme: 'HTTP'
    };

    // This is used to verify that the API is functional.
    local apiHealthCheck = {
        port: apiPort,
        scheme: 'HTTP'
    };

    local namespace = {
        apiVersion: 'v1',
        kind: 'Namespace',
        metadata: {
            name: namespaceName,
            labels: namespaceLabels
        }
    };

    local rateLimitAnnotations = {
        'nginx.ingress.kubernetes.io/limit-rps': '5',
        'nginx.ingress.kubernetes.io/limit-burst-multiplier': '1'
    };

    local tls = util.getTLSConfig(fullyQualifiedName, hosts);
    local ingress = {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'Ingress',
        metadata: {
            name: fullyQualifiedName,
            namespace: namespaceName,
            labels: labels,
            annotations: annotations + tls.ingressAnnotations + util.getAuthAnnotations(config, '.apps.allenai.org') + rateLimitAnnotations + {
                'nginx.ingress.kubernetes.io/ssl-redirect': 'true',
                'nginx.ingress.kubernetes.io/proxy-read-timeout': '120'
            }
        },
        spec: {
            tls: [ tls.spec + { hosts: hosts } ],
            rules: [
                {
                    host: host,
                    http: {
                        paths: [
                            {
                                path: '/',
                                pathType: 'Prefix',
                                backend: {
                                    service: {
                                        name: fullyQualifiedName,
                                        port: {
                                            number: proxyPort
                                        }
                                    }
                                }
                            }
                        ]
                    }
                } for host in hosts
            ]
        }
    };

    local allenAITLS = util.getTLSConfig(fullyQualifiedName + '-allen-dot-ai', allenAIHosts);
    local allenAIIngress = {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'Ingress',
        metadata: {
            name: fullyQualifiedName + '-allen-dot-ai',
            namespace: namespaceName,
            labels: labels,
            annotations: annotations + allenAITLS.ingressAnnotations + util.getAuthAnnotations(config, '.allen.ai') + rateLimitAnnotations + {
                'nginx.ingress.kubernetes.io/ssl-redirect': 'true',
                'nginx.ingress.kubernetes.io/proxy-read-timeout': '120'
            }
        },
        spec: {
            tls: [ allenAITLS.spec + { hosts: allenAIHosts } ],
            rules: [
                {
                    host: host,
                    http: {
                        paths: [
                            {
                                path: '/',
                                pathType: 'Prefix',
                                backend: {
                                    service: {
                                        name: fullyQualifiedName,
                                        port: {
                                            number: proxyPort
                                        }
                                    }
                                }
                            }
                        ]
                    }
                } for host in allenAIHosts
            ]
        }
    };

    local scholarTLS = util.getTLSConfig(fullyQualifiedName + '-scholar', scholarHosts);
    local scholarIngress = {
        apiVersion: 'networking.k8s.io/v1',
        kind: 'Ingress',
        metadata: {
            name: fullyQualifiedName + '-scholar',
            namespace: namespaceName,
            labels: labels,
            annotations: annotations + scholarTLS.ingressAnnotations + util.getAuthAnnotations(config, 'apps.semanticscholar.org') + rateLimitAnnotations + {
                'nginx.ingress.kubernetes.io/ssl-redirect': 'true',
                'nginx.ingress.kubernetes.io/proxy-read-timeout': '120'
            }
        },
        spec: {
            tls: [ scholarTLS.spec + { hosts: scholarHosts } ],
            rules: [
                {
                    host: host,
                    http: {
                        paths: [
                            {
                                path: '/',
                                pathType: 'Prefix',
                                backend: {
                                    service: {
                                        name: fullyQualifiedName,
                                        port: {
                                            number: proxyPort
                                        }
                                    }
                                }
                            }
                        ]
                    }
                } for host in scholarHosts
            ]
        }
    };


    local sharedEnv = [
        {
            name: "PYTHON_ENV",
            value: env
        },
        {
            name: "ATTRIBUTION_QUEUE_URL",
            valueFrom: {
                secretKeyRef: {
                    name: "attribution-worker",
                    key: "ATTRIBUTION_QUEUE_URL"
                }
            }
        }
    ];

    local indexVolumes = [
        {
            name: "infinigram-array-pileval-gpt2",
            persistentVolumeClaim: {
                claimName: "infinigram-pileval-gpt2",
                readOnly: true,
            }
        },
        {
            name: "infinigram-array-olmoe-mix-0924-dclm",
            persistentVolumeClaim: {
                // olmoe-mix-0924 was made before we split dclm and nodclm, this claim is JUST dclm data!
                claimName: "infinigram-olmoe-mix-0924",
                readOnly: true,
            }
        },
        {
            name: "infinigram-array-olmoe-mix-0924-nodclm",
            persistentVolumeClaim: {
                claimName: "infinigram-olmoe-mix-0924-nodclm",
                readOnly: true,
            }
        },
        {
            name: "infinigram-array-v4-olmoe-0125-1b-7b-anneal-adapt",
            persistentVolumeClaim: {
                claimName: "infinigram-v4-olmoe-0125-1b-7b-anneal-adapt",
                readOnly: true,
            }
        },
        {
            name: "infinigram-array-v4-olmo-2-1124-13b-anneal-adapt",
            persistentVolumeClaim: {
                claimName: "infinigram-v4-olmo-2-1124-13b-anneal-adapt",
                readOnly: true,
            }
        },
        {
            name: "infinigram-array-v4-olmo-2-0325-32b-anneal-adapt",
            persistentVolumeClaim: {
                claimName: "infinigram-v4-olmo-2-0325-32b-anneal-adapt",
                readOnly: true,
            }
        },
        {
            name: "infinigram-array-v4-tulu-3-8b-adapt",
            persistentVolumeClaim: {
                claimName: "infinigram-v4-tulu-3-8b-adapt-llama",
                readOnly: true,
            }
        },
        {
            name: "infinigram-array-v4-tulu-3-70b-adapt",
            persistentVolumeClaim: {
                claimName: "infinigram-v4-tulu-3-70b-adapt-llama",
                readOnly: true,
            }
        },
        {
            name: "infinigram-array-v4-tulu-3-405b-adapt",
            persistentVolumeClaim: {
                claimName: "infinigram-v4-tulu-3-405b-adapt-llama",
                readOnly: true,
            }
        },
    ];

    local indexVolumeMounts = [
        {
            mountPath: "/mnt/infinigram-array/v4_pileval_llama",
            name: "infinigram-array-pileval-gpt2",
            readOnly: true,
        },
        {
            mountPath: "/mnt/infinigram-array/olmoe-mix-0924-dclm",
            name: "infinigram-array-olmoe-mix-0924-dclm",
            readOnly: true,
        },
        {
            mountPath: "/mnt/infinigram-array/olmoe-mix-0924-nodclm",
            name: "infinigram-array-olmoe-mix-0924-nodclm",
            readOnly: true,
        },
        {
            mountPath: "/mnt/infinigram-array/v4-olmoe-0125-1b-7b-anneal-adapt",
            name: "infinigram-array-v4-olmoe-0125-1b-7b-anneal-adapt",
            readOnly: true,
        },
        {
            mountPath: "/mnt/infinigram-array/v4-olmo-2-1124-13b-anneal-adapt",
            name: "infinigram-array-v4-olmo-2-1124-13b-anneal-adapt",
            readOnly: true,
        },
        {
            mountPath: "/mnt/infinigram-array/v4-olmo-2-0325-32b-anneal-adapt",
            name: "infinigram-array-v4-olmo-2-0325-32b-anneal-adapt",
            readOnly: true,
        },
        {
            mountPath: "/mnt/infinigram-array/v4-tulu-3-8b-adapt",
            name: "infinigram-array-v4-tulu-3-8b-adapt",
            readOnly: true,
        },
        {
            mountPath: "/mnt/infinigram-array/v4-tulu-3-70b-adapt",
            name: "infinigram-array-v4-tulu-3-70b-adapt",
            readOnly: true,
        },
        {
            mountPath: "/mnt/infinigram-array/v4-tulu-3-405b-adapt",
            name: "infinigram-array-v4-tulu-3-405b-adapt",
            readOnly: true,
        },
    ];

    local deployment = {
        apiVersion: 'apps/v1',
        kind: 'Deployment',
        metadata: {
            labels: labels,
            name: fullyQualifiedName,
            namespace: namespaceName,
            annotations: annotations + {
                'kubernetes.io/change-cause': cause
            }
        },
        spec: {
            strategy: {
                type: 'RollingUpdate',
                rollingUpdate: {
                    maxSurge: numReplicas // This makes deployments faster.
                }
            },
            revisionHistoryLimit: 3,
            replicas: numReplicas,
            selector: {
                matchLabels: selectorLabels
            },
            template: {
                metadata: {
                    name: fullyQualifiedName,
                    namespace: namespaceName,
                    labels: podLabels,
                    annotations: annotations
                },
                spec: {
                    # This block tells the cluster that we'd like to make sure
                    # each instance of your application is on a different node. This
                    # way if a node goes down, your application doesn't:
                    # See: https://kubernetes.io/docs/concepts/configuration/assign-pod-node/#node-isolation-restriction
                    affinity: {
                        podAntiAffinity: {
                            requiredDuringSchedulingIgnoredDuringExecution: [
                                {
                                   labelSelector: {
                                        matchExpressions: [
                                            {
                                                    key: labelName,
                                                    operator: "In",
                                                    values: [ antiAffinityLabels[labelName], ],
                                            } for labelName in std.objectFields(antiAffinityLabels)
                                       ],
                                    },
                                    topologyKey: "kubernetes.io/hostname"
                                },
                            ]
                        },
                    },
                    nodeSelector: {
                        "cloud.google.com/gke-nodepool": "cpu64-256g"
                    },
                    volumes: indexVolumes,
                    containers: [
                        {
                            name: fullyQualifiedName + '-api',
                            image: apiImage,
                            volumeMounts: indexVolumeMounts,
                            # The "probes" below allow Kubernetes to determine
                            # if your application is working properly.
                            #
                            # The readinessProbe is used to determine if
                            # an instance of your application can accept live
                            # requests. The configuration below tells Kubernetes
                            # to stop sending live requests to your application
                            # if it returns 3 non 2XX responses over 30 seconds.
                            # When this happens the application instance will
                            # be taken out of rotation and given time to "catch-up".
                            # Once it returns a single 2XX, Kubernetes will put
                            # it back in rotation.
                            #
                            # Kubernetes also has a livenessProbe that can be used to restart
                            # deadlocked processes. You can find out more about it here:
                            # https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-a-liveness-command
                            #
                            # We don't use a livenessProbe as it's easy to cause unnecessary
                            # restarts, which can be really disruptive to a site's availability.
                            # If you think your application is likely to be unstable after running
                            # for long periods send a note to reviz@allenai.org so we can work
                            # with you to craft the right livenessProbe.
                            readinessProbe: {
                                httpGet: apiHealthCheck + {
                                    path: '/health?check=rdy'
                                },
                                periodSeconds: 10,
                                failureThreshold: 3
                            },
                            # This tells Kubernetes what CPU and memory resources your API needs.
                            # We set these values low by default, as most applications receive
                            # bursts of activity and accordingly don't need dedicated resources
                            # at all times.
                            #
                            # Your application will be allowed to use more resources than what's
                            # specified below. But your application might be killed if it uses
                            # more than what's requested. If you know you need more memory
                            # or that your workload is CPU intensive, consider increasing the
                            # values below.
                            #
                            # For more information about these values, and the current maximums
                            # that your application can request, see:
                            # https://skiff.allenai.org/resources.html
                            resources: {
                                requests: {
                                    cpu: 63,
                                    memory: '257G'
                                },
                                limits: { }
                                   + gpuLimits # only the first container should have gpuLimits applied
                            },
                            env: sharedEnv + [
                                {
                                    name: 'OTEL_SERVICE_NAME',
                                    value: 'infinigram-api'
                                },
                                {
                                    name: 'LOG_FORMAT',
                                    value: 'google:json'
                                },
                                {
                                    name: "CACHE_URL",
                                    valueFrom: {
                                        secretKeyRef: {
                                            name: "api",
                                            key: "CACHE_URL"
                                        }
                                    }
                                }
                            ]
                        },
                        {
                            name: fullyQualifiedName + '-proxy',
                            image: proxyImage,
                            readinessProbe: {
                                httpGet: proxyHealthCheck + {
                                    path: '/proxy_health?check=rdy'
                                }
                            },
                            resources: {
                                requests: {
                                   cpu: 0.1,
                                   memory: '100M'
                                }
                            }
                        }
                    ]
                }
            }
        }
    };

    local service = {
        apiVersion: 'v1',
        kind: 'Service',
        metadata: {
            name: fullyQualifiedName,
            namespace: namespaceName,
            labels: labels,
            annotations: annotations
        },
        spec: {
            selector: selectorLabels,
            ports: [
                {
                    port: proxyPort,
                    name: 'http'
                }
            ]
        }
    };

    local pdb = {
        apiVersion: 'policy/v1',
        kind: 'PodDisruptionBudget',
        metadata: {
            name: fullyQualifiedName,
            namespace: namespaceName,
            labels: labels,
        },
        spec: {
            minAvailable: if numReplicas > 1 then 1 else 0,
            selector: {
                matchLabels: selectorLabels,
            },
        },
    };

    local attributionWorkerReplicas = if env == 'prod' then config.attributionWorkerReplicas.prod else 1;
    local attributionWorkerSelectorLabels = {
        app: config.appName + '-attribution-worker',
        env: env
    };
    local attributionWorkerPodLabels = podLabels + { app: config.appName + '-attribution-worker' };
    local attributionWorkerFullyQualifiedName = fullyQualifiedName + '-attribution-worker';

    // This is used to verify that the worker is functional.
    local workerHealthCheck = {
        port: 8080,
        scheme: 'HTTP'
    };

    local attributionWorkerDeployment = {
        apiVersion: 'apps/v1',
        kind: 'Deployment',
        metadata: {
            labels: labels,
            name: attributionWorkerFullyQualifiedName,
            namespace: namespaceName,
            annotations: annotations + {
                'kubernetes.io/change-cause': cause
            }
        },
        spec: {
            strategy: {
                type: 'RollingUpdate',
                rollingUpdate: {
                    maxSurge: attributionWorkerReplicas // This makes deployments faster.
                }
            },
            revisionHistoryLimit: 3,
            replicas: attributionWorkerReplicas,
            selector: {
                matchLabels: attributionWorkerSelectorLabels
            },
            template: {
                metadata: {
                    name: attributionWorkerFullyQualifiedName,
                    namespace: namespaceName,
                    labels: attributionWorkerPodLabels,
                    annotations: annotations
                },
                spec: {
                    # This block tells the cluster that we'd like to make sure
                    # each instance of your application is on a different node. This
                    # way if a node goes down, your application doesn't:
                    # See: https://kubernetes.io/docs/concepts/configuration/assign-pod-node/#node-isolation-restriction
                    affinity: {
                        podAntiAffinity: {
                            requiredDuringSchedulingIgnoredDuringExecution: [
                                {
                                   labelSelector: {
                                        matchExpressions: [
                                            {
                                                    key: labelName,
                                                    operator: "In",
                                                    values: [ antiAffinityLabels[labelName], ],
                                            } for labelName in std.objectFields(antiAffinityLabels)
                                       ],
                                    },
                                    topologyKey: "kubernetes.io/hostname"
                                },
                            ]
                        },
                    },
                    nodeSelector: {
                        "cloud.google.com/gke-nodepool": "cpu64-256g"
                    },
                    volumes: indexVolumes,
                    containers: [
                        {
                            name: attributionWorkerFullyQualifiedName,
                            image: workerImage,
                            volumeMounts: indexVolumeMounts,
                            # The "probes" below allow Kubernetes to determine
                            # if your application is working properly.
                            #
                            # The readinessProbe is used to determine if
                            # an instance of your application can accept live
                            # requests. The configuration below tells Kubernetes
                            # to stop sending live requests to your application
                            # if it returns 3 non 2XX responses over 30 seconds.
                            # When this happens the application instance will
                            # be taken out of rotation and given time to "catch-up".
                            # Once it returns a single 2XX, Kubernetes will put
                            # it back in rotation.
                            #
                            # Kubernetes also has a livenessProbe that can be used to restart
                            # deadlocked processes. You can find out more about it here:
                            # https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/#define-a-liveness-command
                            #
                            # We don't use a livenessProbe as it's easy to cause unnecessary
                            # restarts, which can be really disruptive to a site's availability.
                            # If you think your application is likely to be unstable after running
                            # for long periods send a note to reviz@allenai.org so we can work
                            # with you to craft the right livenessProbe.
                            readinessProbe: {
                                httpGet: workerHealthCheck + {
                                    path: '/'
                                },
                                periodSeconds: 10,
                                failureThreshold: 3
                            },
                            # This tells Kubernetes what CPU and memory resources your API needs.
                            # We set these values low by default, as most applications receive
                            # bursts of activity and accordingly don't need dedicated resources
                            # at all times.
                            #
                            # Your application will be allowed to use more resources than what's
                            # specified below. But your application might be killed if it uses
                            # more than what's requested. If you know you need more memory
                            # or that your workload is CPU intensive, consider increasing the
                            # values below.
                            #
                            # For more information about these values, and the current maximums
                            # that your application can request, see:
                            # https://skiff.allenai.org/resources.html
                            resources: {
                                requests: {
                                    cpu: 63,
                                    memory: '257G'
                                },
                                limits: { }
                                   + gpuLimits # only the first container should have gpuLimits applied
                            },
                            env: sharedEnv + [
                                {
                                    name: 'OTEL_SERVICE_NAME',
                                    value: 'infinigram-api-worker'
                                },
                            ]
                        }
                    ]
                }
            }
        }
    };

    local defaultObjects = [
        namespace,
        ingress,
        allenAIIngress,
        deployment,
        service,
        pdb,
        attributionWorkerDeployment
    ];

    if std.length(scholarHosts) > 0 then
        defaultObjects + [ scholarIngress ]
    else
        defaultObjects

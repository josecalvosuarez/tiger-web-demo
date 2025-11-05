#!/usr/bin/env bash
set -euo pipefail

NS="rollback-ctf"
APP_NAME="webapp"

echo ">>> Creating namespace: ${NS}"
kubectl get ns "${NS}" >/dev/null 2>&1 || kubectl create namespace "${NS}"

echo ">>> Creating / updating deployment through 10 revisions"
echo

deploy_revision() {
  local rev="$1"
  local image="$2"
  local quality="$3"   # good | bad | broken
  local flag="$4"
  local cause="$5"

  echo ">>> Deploying revision ${rev} (quality=${quality})"

  kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${APP_NAME}
  namespace: ${NS}
spec:
  replicas: 2
  selector:
    matchLabels:
      app: ${APP_NAME}
  template:
    metadata:
      labels:
        app: ${APP_NAME}
        version: "v${rev}"
        ctf-revision: "rev-${rev}"
        ctf-quality: "${quality}"
    spec:
      containers:
      - name: ${APP_NAME}
        image: ${image}
        ports:
        - containerPort: 80
        env:
        - name: FLAG
          value: "${flag}"
EOF

  kubectl annotate deployment "${APP_NAME}" \
    -n "${NS}" \
    kubernetes.io/change-cause="${cause}" \
    --overwrite

  # For broken revisions, don't fail the whole script if rollout doesn't complete
  if [[ "${quality}" == "broken" ]]; then
    kubectl rollout status deployment/${APP_NAME} -n "${NS}" --timeout=30s || true
  else
    kubectl rollout status deployment/${APP_NAME} -n "${NS}"
  fi

  echo
}

# -----------------------------
# Revision definitions
# Good revisions (with flags): 2, 5, 7
# Final revision (10) is broken
# -----------------------------

# Revision 1 – baseline (bad for CTF, but technically healthy)
deploy_revision \
  1 \
  "nginx:1.19" \
  "bad" \
  "NO_FLAG_IN_REV1" \
  "Initial baseline release v1 (no flag)"

# Create Service after first revision
echo ">>> Creating Service for ${APP_NAME}"
kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: ${APP_NAME}
  namespace: ${NS}
spec:
  selector:
    app: ${APP_NAME}
  ports:
  - name: http
    port: 80
    targetPort: 80
EOF
echo

# Revision 2 – GOOD (flag #1)
deploy_revision \
  2 \
  "nginx:1.20" \
  "good" \
  "FLAG{REV2_FIRST_GOOD}" \
  "v2 rollout (GOOD) - includes first flag"

# Revision 3 – bad (but still healthy)
deploy_revision \
  3 \
  "nginx:1.21" \
  "bad" \
  "NO_FLAG_IN_REV3" \
  "v3 rollout (BAD for CTF - no flag)"

# Revision 4 – bad (still healthy)
deploy_revision \
  4 \
  "nginx:1.22" \
  "bad" \
  "NO_FLAG_IN_REV4" \
  "v4 rollout (BAD for CTF - no flag)"

# Revision 5 – GOOD (flag #2)
deploy_revision \
  5 \
  "nginx:1.23" \
  "good" \
  "FLAG{REV5_SECOND_GOOD}" \
  "v5 rollout (GOOD) - includes second flag"

# Revision 6 – bad
deploy_revision \
  6 \
  "nginx:1.24" \
  "bad" \
  "NO_FLAG_IN_REV6" \
  "v6 rollout (BAD for CTF - no flag)"

# Revision 7 – GOOD (flag #3)
deploy_revision \
  7 \
  "nginx:1.25" \
  "good" \
  "FLAG{REV7_THIRD_GOOD}" \
  "v7 rollout (GOOD) - includes third flag"

# Revision 8 – bad
deploy_revision \
  8 \
  "nginx:1.26" \
  "bad" \
  "NO_FLAG_IN_REV8" \
  "v8 rollout (BAD for CTF - no flag)"

# Revision 9 – bad
deploy_revision \
  9 \
  "nginx:1.27" \
  "bad" \
  "NO_FLAG_IN_REV9" \
  "v9 rollout (BAD for CTF - no flag)"

# Revision 10 – BROKEN (final state)
deploy_revision \
  10 \
  "nginx:this-tag-does-not-exist" \
  "broken" \
  "FLAG_IN_BROKEN_REV10_SHOULD_NOT_USE" \
  "v10 rollout (BROKEN image - incident!)"

echo "=============================================="
echo " SETUP COMPLETE"
echo " Namespace: ${NS}"
echo " Deployment: ${APP_NAME}"
echo " Service:    ${APP_NAME} (ClusterIP, port 80)"
echo
echo " Current state (revision 10 should be BROKEN):"
kubectl get deploy,rs,pods,svc -n "${NS}"
echo
echo " Rollout history:"
kubectl rollout history deployment/${APP_NAME} -n "${NS}"
echo
cat <<'INSTRUCTIONS'

>>> STUDENT MISSION

An incident has occurred: the latest rollout (revision 10) is broken.

Your tasks:

1) Inspect the rollout history:

2) Use rollbacks to explore different revisions.


3) For the CURRENTLY ACTIVE revision, check pod labels:
   # Look at: ctf-revision and ctf-quality

4) For the CURRENTLY ACTIVE revision, capture the FLAG:
   POD=$(kubectl -n rollback-ctf get pod -l app=webapp -o jsonpath='{.items[0].metadata.name}')
   kubectl -n rollback-ctf exec -it "$POD" -- printenv FLAG

5) Your goal:
   - Find the three revisions where:
       label ctf-quality=good
     and retrieve all three FLAG values.

INSTRUCTIONS
echo "=============================================="

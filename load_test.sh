#!/bin/bash
# load_test.sh — Carga progressiva de UEs + tráfego automático
# TCC Leonardo Morais de Souza — IFPB 2026


MAX_UES=20
INTERVALO=30
REQUISICOES=100
LOG="resultados_$(date +%Y%m%d_%H%M%S).csv"


echo "timestamp,batch,ues_total,replicas_upf,cpu_upf_m" > "$LOG"


UES_TOTAL=1; MSISDN=2; BATCH=0


gerar_trafego() {
  kubectl exec deployment/$1 -- bash -c \
    "for i in $(seq 1 $REQUISICOES); do \
     curl -s --interface $2 https://www.google.com > /dev/null; done" &
}


UE_IP=$(kubectl exec deployment/ueransim-gnb-ues -- \
  ip addr show uesimtun0 2>/dev/null | grep "inet " | \
  awk '{print $2}' | cut -d'/' -f1)
[ ! -z "$UE_IP" ] && gerar_trafego "ueransim-gnb-ues" "$UE_IP"


while [ $UES_TOTAL -lt $MAX_UES ]; do
  BATCH=$(( BATCH + 1 ))
  MSISDN_FMT=$(printf "%010d" $MSISDN)
  helm install -n default "ueransim-ues-batch${BATCH}" ./ueransim-ues \
    --set gnb.hostname=ueransim-gnb --set ues.count=1 \
    --set ues.initialMSISDN="$MSISDN_FMT" \
    --wait --timeout 60s > /dev/null 2>&1
  sleep 10
  REAL_DEPLOY=$(kubectl get deployment --no-headers 2>/dev/null \
    | grep "ueransim-ues-batch${BATCH}" | awk '{print $1}' | head -1)
  UE_IP=$(kubectl exec deployment/$REAL_DEPLOY -- \
    ip addr show uesimtun0 2>/dev/null | grep "inet " | \
    awk '{print $2}' | cut -d'/' -f1)
  [ ! -z "$UE_IP" ] && gerar_trafego "$REAL_DEPLOY" "$UE_IP"
  sleep $(( INTERVALO - 10 ))
  REPLICAS=$(kubectl get hpa open5gs-upf \
    -o jsonpath="{.status.currentReplicas}" 2>/dev/null || echo "1")
  CPU=$(kubectl top pods -l app.kubernetes.io/name=upf \
    --no-headers 2>/dev/null | awk '{gsub(/m/,"",$2); sum+=$2} END {print sum+0}')
  echo "$(date +"%Y-%m-%d %H:%M:%S"),$BATCH,$((UES_TOTAL+1)),$REPLICAS,${CPU:-0}" >> "$LOG"
  UES_TOTAL=$(( UES_TOTAL + 1 ))
  MSISDN=$(( MSISDN + 1 ))
  [ "${REPLICAS:-1}" -ge 5 ] && break
done
echo "Fim: $(date) | Resultados: $LOG"

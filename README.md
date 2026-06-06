# OCI A1 Creator Easy

Windows에서 Oracle Cloud Always Free A1 인스턴스(`VM.Standard.A1.Flex`)를 반복 생성하는 PowerShell 자동화입니다.

기본값은 4 OCPU, 24 GB RAM, 200 GB boot volume입니다. 생성 실패 사유는 매 시도마다 Discord webhook으로 전송할 수 있습니다.

## 준비물

- OCI 계정
- OCI API private key `.pem`
- OCI API key의 `user`, `fingerprint`, `tenancy`, `region`
- Discord webhook URL, 선택 사항

OCI API key 값은 콘솔에서 확인합니다.

```text
Profile > User settings > Tokens and keys > API keys
```

## 빠른 시작

PowerShell에서:

```powershell
git clone https://github.com/swan2913/oci-a1-creator-easy.git
cd oci-a1-creator-easy

powershell -ExecutionPolicy Bypass -File .\scripts\setup.ps1
powershell -ExecutionPolicy Bypass -File .\scripts\install-task.ps1
```

`setup.ps1`은 아래 작업을 수행합니다.

- `uv` 확인
- `oci-cli` 설치
- `~\.oci\config` 생성
- SSH public key 확인 또는 생성
- availability domain 조회
- VCN, Internet Gateway, public subnet 생성 또는 재사용
- 최신 Ubuntu ARM 이미지 선택
- `config.local.json` 생성

`install-task.ps1`은 Windows Scheduled Task `OCI-A1-Creator`를 등록하고 1분마다 실행합니다.

## 수동 1회 실행

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run-once.ps1
```

## 상태 확인

```powershell
Get-ScheduledTask -TaskName OCI-A1-Creator
Get-ScheduledTaskInfo -TaskName OCI-A1-Creator
Get-Content -Tail 80 "$env:USERPROFILE\.oci\a1-creator\launch.log"
```

## 중지

```powershell
Disable-ScheduledTask -TaskName OCI-A1-Creator
```

## 재시작

```powershell
Enable-ScheduledTask -TaskName OCI-A1-Creator
Start-ScheduledTask -TaskName OCI-A1-Creator
```

## 삭제

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\uninstall-task.ps1
```

## 알림

`config.local.json`의 `discordWebhookUrl`에 URL을 넣으면 매 실패마다 다음 정보를 보냅니다.

- attempt 번호
- exit code
- OCI status
- OCI code
- OCI message
- operation
- opc-request-id

성공하면 인스턴스 OCID를 보내고 Scheduled Task를 자동 비활성화합니다.

## 주의

- `config.local.json`과 `.pem` 파일은 git에 올라가지 않습니다.
- webhook URL은 공개 repo에 올리지 마세요.
- `Out of host capacity`는 정상적인 실패입니다. 용량이 생길 때까지 재시도합니다.
- `TooManyRequests`가 자주 나오면 반복 주기를 늘리세요.
- 200 GB boot volume은 Always Free block/boot volume 한도를 모두 사용합니다. 서버 1대만 쓸 때 권장합니다.
- 생성 후에는 반드시 Discord webhook을 삭제하거나 재발급하세요.

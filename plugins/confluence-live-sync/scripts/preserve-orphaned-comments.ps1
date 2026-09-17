<#
.SYNOPSIS
  Safeguard for Confluence inline comments across a full-body page republish
  (e.g. the markdown-push + HTML-patch two-pass workflow used by
  confluence-live-sync / pickit-sync-kickoff).

.DESCRIPTION
  Full-body content replaces can delete-and-recreate the content node an
  inline comment is anchored to, orphaning the comment (it still exists on
  the page but loses its highlighted anchor). Footer/page-level comments are
  never affected by this and need no handling.

  Usage pattern around a publish:
    1. Before editing the page body, call -Mode Snapshot to capture every
       inline comment's anchored text + body + author into a local JSON file.
    2. Do the publish (markdown push, then HTML patch, etc.) as normal.
    3. After publishing, call -Mode Reconcile: it re-fetches inline comments,
       diffs against the snapshot, and for every comment that no longer
       resolves (orphaned), posts a footer/page comment preserving the
       original anchored paragraph text + comment body + author, so nothing
       is silently lost even without the highlight.

.NOTES
  Requires $env:CONFLUENCE_API_TOKEN (see Get-ConfluenceApiToken pattern used
  elsewhere in the plugin skills — this script uses the same resilient lookup).
  Uses Confluence REST API v2 for inline comments and REST API v1 for footer
  comments (v1 footer-comment endpoint is stable and simple to POST to).

  KNOWN GOTCHA — do not "simplify" orphan-detection back to resolutionStatus
  or comment-ID presence: confirmed on page 3233677317 (2026-09-14) that a
  full-body markdown push strips inline-comment anchor marks from the ENTIRE
  page body (not just edited paragraphs — markdown has no way to represent an
  anchor mark at all), yet the comment OBJECT itself is untouched: its ID
  keeps existing and the API keeps reporting resolutionStatus "open", never
  "dangling", even though the highlight is gone from the live page. So orphan
  detection MUST diff the snapshot's anchored text against the CURRENT page
  content (substring containment), not against comment IDs or resolutionStatus
  — both of those looked fine while 10 comments were silently invisible.
#>

param(
  [Parameter(Mandatory = $true)][ValidateSet("Snapshot", "Reconcile")]
  [string]$Mode,

  [Parameter(Mandatory = $true)][string]$PageId,

  [string]$SnapshotPath = (Join-Path $PSScriptRoot "inline-comments-snapshot.json"),

  [string]$SiteBaseUrl = "https://pickit.atlassian.net/wiki",

  [string]$AccountEmail = "pvallarino@pickit.net"
)

function Get-ConfluenceApiToken {
  $raw = $env:CONFLUENCE_API_TOKEN
  if (-not $raw) { $raw = [Environment]::GetEnvironmentVariable("CONFLUENCE_API_TOKEN", "User") }
  if (-not $raw) { $raw = [Environment]::GetEnvironmentVariable("CONFLUENCE_API_TOKEN", "Machine") }
  if ($raw) { return $raw.Trim() }
  return $null
}

$token = Get-ConfluenceApiToken
if (-not $token) {
  Write-Error "CONFLUENCE_API_TOKEN not found (checked process/User/Machine env). Create one at id.atlassian.com/manage-profile/security/api-tokens."
  exit 1
}
$authPair = "${AccountEmail}:$token"
$auth = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($authPair))
$headers = @{ Authorization = "Basic $auth"; "X-Atlassian-Token" = "no-check" }

function Get-InlineComments {
  param([string]$PageId)
  # v2: inline comments for a page, expanded with body + resolution status.
  $uri = "$SiteBaseUrl/api/v2/pages/$PageId/inline-comments?body-format=atlas_doc_format&limit=250"
  $all = @()
  do {
    $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
    $all += $resp.results
    $next = $resp._links.next
    $uri = if ($next) { "$SiteBaseUrl$next" } else { $null }
  } while ($uri)
  return $all
}

if ($Mode -eq "Snapshot") {
  $comments = Get-InlineComments -PageId $PageId
  $snapshot = $comments | ForEach-Object {
    [PSCustomObject]@{
      id              = $_.id
      status           = $_.properties.resolutionStatus
      author           = $_.version.authorId
      createdAt        = $_.createdAt
      # Original highlighted text Confluence anchors the comment to.
      originalSelection = $_.inlineCommentProperties.textSelection
      body             = ($_.body.atlas_doc_format.value)
    }
  }
  $snapshot | ConvertTo-Json -Depth 10 | Set-Content -Path $SnapshotPath -Encoding utf8
  Write-Output "Snapshotted $($snapshot.Count) inline comment(s) to $SnapshotPath"
  exit 0
}

if ($Mode -eq "Reconcile") {
  if (-not (Test-Path $SnapshotPath)) {
    Write-Error "No snapshot found at $SnapshotPath — run -Mode Snapshot before publishing."
    exit 1
  }
  $before = Get-Content $SnapshotPath -Raw | ConvertFrom-Json
  $after = Get-InlineComments -PageId $PageId
  $afterIds = $after | ForEach-Object { $_.id }

  $reconciledLogPath = Join-Path (Split-Path $SnapshotPath -Parent) "inline-comments-reconciled-log.json"
  $reconciledIds = @()
  if (Test-Path $reconciledLogPath) {
    $reconciledIds = @(Get-Content $reconciledLogPath -Raw | ConvertFrom-Json)
  }

  # Fetch current page content as plain text so we can check whether each
  # snapshotted comment's anchored text still actually appears on the page.
  # This is the real signal — comment IDs and resolutionStatus both survive
  # a markdown-push anchor-strip untouched, so neither can be trusted alone.
  $pageUri = "$SiteBaseUrl/api/v2/pages/$PageId?body-format=storage"
  $pageResp = Invoke-RestMethod -Uri $pageUri -Headers $headers -Method Get
  $pageText = $pageResp.body.storage.value -replace '<[^>]+>', ' ' -replace '\s+', ' '

  $orphaned = $before | Where-Object {
    $c = $_
    if ($c.id -in $reconciledIds) { return $false }  # already reconciled on a prior run
    $idGone = ($c.id -notin $afterIds)
    $anchorGone = $false
    if ($c.originalSelection) {
      # Compare a stable prefix (selections are often ellipsized) — 60 chars
      # is short enough to survive minor rewording but long enough to avoid
      # false negatives from generic short phrases.
      $probe = $c.originalSelection.Substring(0, [Math]::Min(60, $c.originalSelection.Length)).Trim()
      if ($probe -and ($pageText -notlike "*$probe*")) { $anchorGone = $true }
    }
    ($idGone -or $anchorGone)
  }

  if (-not $orphaned -or $orphaned.Count -eq 0) {
    Write-Output "No orphaned inline comments detected. Nothing to do."
    exit 0
  }

  foreach ($c in $orphaned) {
    $contextText = if ($c.originalSelection) { $c.originalSelection } else { "(contexto original no disponible)" }
    $footerBody = @"
<p><em>⚠️ Comentario recuperado — se orfanó al republicar la página (el párrafo al que estaba anclado fue reemplazado). Contexto y contenido original preservados abajo:</em></p>
<blockquote><p>$contextText</p></blockquote>
<p>$($c.body)</p>
"@
    $footerUri = "$SiteBaseUrl/rest/api/content/$PageId/child/comment"
    $footerPayload = @{
      type      = "comment"
      container = @{ id = $PageId; type = "page" }
      body      = @{
        storage = @{ value = $footerBody; representation = "storage" }
      }
    } | ConvertTo-Json -Depth 10

    Invoke-RestMethod -Uri $footerUri -Method Post -Headers ($headers + @{ "Content-Type" = "application/json" }) -Body $footerPayload | Out-Null
    Write-Output "Re-posted orphaned comment $($c.id) as a footer comment."
    $reconciledIds += $c.id
  }

  $reconciledIds | ConvertTo-Json -Depth 5 | Set-Content -Path $reconciledLogPath -Encoding utf8
  Write-Output "Reconciled $($orphaned.Count) orphaned inline comment(s) into footer comments."
  exit 0
}

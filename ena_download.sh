#!/usr/bin/env bash

#SBATCH --job-name=ena_download
#SBATCH --output=ena_download%j.log
#SBATCH --time=72:00:00
#SBATCH --mem=4G
#SBATCH --cpus-per-task=1

set -e

# Usage: ./ena_download.sh biosamples.txt

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 biosamples.txt"
  exit 1
fi

BIOSAMPLES_FILE="$1"
OUTDIR="./fastq_files"

CSV_FILE="biosample_to_sra_mapping_${SLURM_JOB_ID:-local}.csv"

mkdir -p "$OUTDIR"

echo "biosample_id,run_accession,fastq_file,download_url" > "$CSV_FILE"

echo "Reading BioSample IDs from $BIOSAMPLES_FILE..."
echo "Writing to CSV: $CSV_FILE"

while IFS= read -r biosample || [ -n "$biosample" ]; do
  [[ -z "$biosample" ]] && continue
  
  biosample=$(echo "$biosample" | tr -d '[:space:]')
  
  echo ""
  echo "Processing: $biosample"

  response=$(curl -s "https://www.ebi.ac.uk/ena/portal/api/filereport?accession=${biosample}&result=read_run&fields=run_accession,fastq_ftp&format=tsv")
 
  if [[ -z "$response" ]] || [[ "$response" == "run_accession"* && $(echo "$response" | wc -l) -eq 1 ]]; then
    echo "  WARNING: No runs found for $biosample"
    continue
  fi

  echo "$response" | tail -n +2 | while IFS=$'\t' read -r run_accession fastq_ftp; do
    [[ -z "$run_accession" ]] && continue
    
    echo "  Found run: $run_accession"

    IFS=';' read -ra URLS <<< "$fastq_ftp"
    
    for url in "${URLS[@]}"; do
      if [[ ! "$url" =~ ^ftp:// ]]; then
        url="ftp://$url"
      fi

      filename=$(basename "$url")
      
      echo "    Downloading: $filename"
      
      wget -q --show-progress -P "$OUTDIR" "$url" || {
        echo "    ERROR: Failed to download $url"
        continue
      }

      echo "${biosample},${run_accession},${filename},${url}" >> "$CSV_FILE"
    done
  done
  
done < "$BIOSAMPLES_FILE"

echo ""
echo "Done!"
echo "Downloaded files are in: $OUTDIR/"
echo "Mapping CSV file: $CSV_FILE"
echo ""
echo "Summary:"
echo "  Total files downloaded: $(ls -1 "$OUTDIR" 2>/dev/null | wc -l)"
echo "  CSV entries: $(($(wc -l < "$CSV_FILE") - 1))"
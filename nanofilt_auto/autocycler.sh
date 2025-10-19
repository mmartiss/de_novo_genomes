#!/bin/bash

#SBATCH --job-name=autocycler
#SBATCH --output=autocycler_%j.log
#SBATCH -p gpu
#SBATCH --cpus-per-task=8
#SBATCH --mem=32G
#SBATCH --gres=gpu:1
#SBATCH --time=4:00:00

set -e

# Conda setup
__conda_setup="$('/scratch/lustre/home/maab9325/miniforge3/bin/conda' 'shell.bash' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/scratch/lustre/home/maab9325/miniforge3/etc/profile.d/conda.sh" ]; then
        . "/scratch/lustre/home/maab9325/miniforge3/etc/profile.d/conda.sh"
    else
        export PATH="/scratch/lustre/home/maab9325/miniforge3/bin:$PATH"
    fi
fi
unset __conda_setup

conda activate autocycler
cd ~/de_novo_genomes

# ============================================
# Parameters
# ============================================
READS="filtered_SRR34323118.fastq"  # Tavo NanoFilt output
THREADS=8
READ_TYPE="ont_r10"  # MinION R10 chemistry (arba ont_r9 jei senesnis)

echo "=========================================="
echo "Autocycler Pipeline"
echo "Input: ${READS}"
echo "Started: $(date)"
echo "=========================================="

# Check input file
if [[ ! -f "$READS" ]]; then
    echo "ERROR: Input file '$READS' not found!"
    exit 1
fi

# ============================================
# STEP 1: Estimate genome size
# ============================================
echo ""
echo "[$(date)] STEP 1: Estimating genome size..."
GENOME_SIZE=$(autocycler helper genome_size --reads "$READS" --threads "$THREADS" 2>&1 | tee logs/01_genome_size.log | tail -1)
echo "Estimated genome size: ${GENOME_SIZE}"

# ============================================
# STEP 2: Subsample reads
# ============================================
echo ""
echo "[$(date)] STEP 2: Subsampling reads..."
autocycler subsample \
    --reads "$READS" \
    --out_dir subsampled_reads \
    --genome_size "$GENOME_SIZE" \
    2>&1 | tee logs/02_subsample.log

# ============================================
# STEP 3: Run assemblies (Flye only)
# ============================================
echo ""
echo "[$(date)] STEP 3: Running assemblies..."
mkdir -p assemblies

# Run Flye on each subsampled read set
for i in 01 02 03 04; do
    if [ -f "subsampled_reads/sample_${i}.fastq" ]; then
        echo "[$(date)] Assembling sample ${i} with Flye..."
        autocycler helper flye \
            --reads "subsampled_reads/sample_${i}.fastq" \
            --out_prefix "assemblies/flye_${i}" \
            --threads "$THREADS" \
            --genome_size "$GENOME_SIZE" \
            --read_type "$READ_TYPE" \
            --min_depth_rel 0.1 \
            2>&1 | tee "logs/03_flye_${i}.log"
    fi
done

# Give Flye contigs extra consensus weight
for f in assemblies/flye*.fasta; do
    if [ -f "$f" ]; then
        sed -i 's/^>.*$/& Autocycler_consensus_weight=2/' "$f"
    fi
done

# Clean up subsampled reads
rm -f subsampled_reads/*.fastq

# ============================================
# STEP 4: Compress into unitig graph
# ============================================
echo ""
echo "[$(date)] STEP 4: Compressing assemblies..."
autocycler compress \
    -i assemblies \
    -a autocycler_out \
    2>&1 | tee logs/04_compress.log

# ============================================
# STEP 5: Cluster contigs
# ============================================
echo ""
echo "[$(date)] STEP 5: Clustering contigs..."
autocycler cluster \
    -a autocycler_out \
    2>&1 | tee logs/05_cluster.log

# ============================================
# STEP 6 & 7: Trim and resolve each cluster
# ============================================
echo ""
echo "[$(date)] STEP 6-7: Trimming and resolving clusters..."
for c in autocycler_out/clustering/qc_pass/cluster_*; do
    if [ -d "$c" ]; then
        cluster_name=$(basename "$c")
        echo "[$(date)] Processing ${cluster_name}..."
        
        autocycler trim -c "$c" 2>&1 | tee "logs/06_trim_${cluster_name}.log"
        autocycler resolve -c "$c" 2>&1 | tee "logs/07_resolve_${cluster_name}.log"
    fi
done

# ============================================
# STEP 8: Combine into final assembly
# ============================================
echo ""
echo "[$(date)] STEP 8: Creating final assembly..."
autocycler combine \
    -a autocycler_out \
    -i autocycler_out/clustering/qc_pass/cluster_*/5_final.gfa \
    2>&1 | tee logs/08_combine.log

# ============================================
# STEP 9: Convert to FASTA
# ============================================
echo ""
echo "[$(date)] STEP 9: Converting to FASTA..."
if [ -f "autocycler_out/final_assembly/final_assembly.gfa" ]; then
    autocycler gfa2fasta \
        autocycler_out/final_assembly/final_assembly.gfa \
        autocycler_out/final_assembly/final_assembly.fasta \
        2>&1 | tee logs/09_gfa2fasta.log
fi

# ============================================
# Summary
# ============================================
echo ""
echo "=========================================="
echo "Pipeline completed: $(date)"
echo "=========================================="
echo ""

if [ -f "autocycler_out/final_assembly/final_assembly.fasta" ]; then
    CONTIG_COUNT=$(grep -c "^>" "autocycler_out/final_assembly/final_assembly.fasta")
    echo "✓ Final assembly created: ${CONTIG_COUNT} contigs"
    echo ""
    echo "Results:"
    echo "  Final assembly: autocycler_out/final_assembly/final_assembly.fasta"
    echo "  GFA file:       autocycler_out/final_assembly/final_assembly.gfa"
    echo "  All logs:       logs/"
    echo ""
    echo "First few contigs:"
    grep "^>" "autocycler_out/final_assembly/final_assembly.fasta" | head -5
else
    echo "✗ WARNING: Final assembly not found!"
fi

echo "=========================================="
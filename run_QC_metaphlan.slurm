#!/bin/bash
#SBATCH -p batch
#SBATCH -n 30
#SBATCH --comment=test
# Input: paired gzipped FASTQ files named <sample>_1.fastq.gz and <sample>_2.fastq.gz in the working directory.
# Input: adapter FASTA, indexed hg38 reference, and MetaPhlAn database; configure the site-specific paths before submission.

srun='srun --nodes 1 --ntasks 1 --cpus-per-task 5'
parallel='parallel --xapply --max-procs 6'

mkdir raw
mv ./*.fastq.gz ./raw

$parallel "$srun java -jar /public/software/apps/Trimmomatic-0.39/trimmomatic-0.39.jar PE -phred33 -threads 5 {1} {2} -baseout {3}_trim.fastq.gz ILLUMINACLIP:/public/software/apps/Trimmomatic-0.39/adapters/TruSeq3-PE.fa:2:30:10:1:true LEADING:3 TRAILING:3 SLIDINGWINDOW:4:15 AVGQUAL:15 MINLEN:60" ::: `ls raw/*_1.fastq.gz` ::: `ls raw/*_2.fastq.gz` ::: `ls raw | grep '_1.fastq.gz$' | sed 's/_1.fastq.gz//g'`

mkdir -p trim || exit 1
mv ./*trim* ./trim

$parallel "$srun  bwa mem -t 5 -M /public/bio/database/bwa_hg38/hg38.fa {1} {2} > {3}" ::: `ls trim/*_1P.fastq.gz` ::: `ls trim/*_2P.fastq.gz` ::: `ls trim | grep _trim_1P.fastq.gz | sed 's/_trim_1P.fastq.gz/_pe.sam/g'`

mkdir sam
mv ./*_pe.sam ./sam

$parallel "$srun  samtools view -bS {1} -o {2} -@ 5" ::: `ls sam/*` ::: `ls sam/ | sed 's/sam/bam/g'`

mkdir sam2bam
mv ./*_pe.bam ./sam2bam

$parallel "$srun  samtools view -b -f 12 -F 256 {1} -o {2} -@ 5" ::: `ls sam2bam/*` ::: `ls sam2bam/ | sed 's/pe/pe-Unmapped/g'`

mkdir unmap
mv ./*_pe-Unmapped.bam ./unmap

$parallel "$srun  samtools sort -n {1} -o {2} -@ 5" ::: `ls unmap/*` ::: `ls unmap/ | sed 's/Unmapped/Unmapped_sorted/g'`

mkdir sortbam
mv ./*_pe-Unmapped_sorted.bam ./sortbam

$parallel "$srun  bedtools bamtofastq -i {1} -fq {2}_r1.fastq -fq2 {2}_r2.fastq" ::: `ls sortbam/*` ::: `ls sortbam/ | sed 's/_pe-Unmapped_sorted.bam/_removed/g'`

mkdir clean
mv ./*removed* ./clean

$parallel "$srun pigz -p 5 {1} {2}" ::: `ls clean/*_r1.fastq` ::: `ls clean/*_r2.fastq`

srun='srun --nodes 1 --ntasks 1 --cpus-per-task 5'
parallel='parallel --xapply --max-procs 6'

$parallel "$srun  metaphlan {1},{2} --bowtie2out {3}.bowtie2.bz2 --nproc 5 --input_type fastq -t rel_ab_w_read_stats \
        -o {3}.txt" \
        ::: `ls *removed_r1.fastq.gz` \
        ::: `ls *removed_r2.fastq.gz` \
        ::: `ls | grep removed_r1.fastq.gz | sed 's/removed_r1.fastq.gz//g'`

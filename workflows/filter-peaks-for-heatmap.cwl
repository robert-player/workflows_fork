cwlVersion: v1.0
class: Workflow


requirements:
  - class: SubworkflowFeatureRequirement
  - class: StepInputExpressionRequirement
  - class: InlineJavascriptRequirement
  - class: MultipleInputFeatureRequirement


'sd:upstream':
  sample_to_filter:
    - "chipseq-se.cwl"
    - "chipseq-pe.cwl"
    - "trim-chipseq-se.cwl"
    - "trim-chipseq-pe.cwl"
    - "trim-atacseq-se.cwl"
    - "trim-atacseq-pe.cwl"


inputs:

  alias:
    type: string
    label: "Experiment short name/Alias"
    sd:preview:
      position: 1

  indices_folder:
    type: Directory
    'sd:upstreamSource': "genome_indices/bowtie_indices"
    label: "Reference genome for samples:"
    doc: "Path to indexed genome folder by **bowtie**, used for IGV of peaks"
    sd:preview:
      position: 2

  annotation_file:
    type: File
    'sd:upstreamSource': "genome_indices/annotation"
    label: "Annotation file"
    format: "http://edamontology.org/format_3475"
    doc: "Tab-separated annotation file"

  feature_file:
    type: File
    format: "http://edamontology.org/format_3475"
    label: "ChIP/ATAC experiment"
    doc: "Called peaks file in TSV format with the nearest genes assigned"
    'sd:upstreamSource': "sample_to_filter/iaintersect_result"
    'sd:localLabel': true

  # alignment_file:
  #   type: File
  #   secondaryFiles:
  #   - .bai
  #   format: "http://edamontology.org/format_2572"
  #   label: "ChIP/ATAC experiment"
  #   doc: "Coordinate sorted BAM and BAI index files"
  #   'sd:upstreamSource': "sample_to_filter/bambai_pair"

  sql_query:
    type: string
    label: "Filtering parameters"
    doc: "Filtering parameters (WHERE parameters for SQL query)"
    'sd:filtering':
      params:
        columns: ["refseq_id", "gene_id", "txStart", "txEnd", "strand", "chrom", "start", "end", "length", "abssummit", "pileup", "log10p", "foldenrich", "log10q", "region"]
        types:   ["string", "string", "number", "number","string", "string","number", "number", "number", "number", "number", "number", "number", "number", "string"]

  header:
    type: boolean?
    default: false
    label: "Include header line"
    doc: "Print header line in the output file"
    'sd:layout':
      advanced: true

  columns:
    type:
    - "null"
    - string[]
    default: ["chrom", "start", "end", "chrom || '-' || start || '-' || end AS name"]
    label: "Columns to print"
    doc: |
      List of columns to print (SELECT parameters for SQL query).
      Need to have format [chrom start end name]. No header.
      4th columns should be unique, so we use a combination of chrom-start-end.
    'sd:layout':
      advanced: true

  promoter_dist:
    type: int?
    default: 1000
    'sd:layout':
      advanced: true
    label: "Max distance from gene TSS for promoter region assignment:"
    doc: "Max distance from gene TSS (in both directions) for peak to be assigned to the promoter region."

  upstream_dist:
    type: int?
    default: 20000
    'sd:layout':
      advanced: true
    label: "Max distance from the promoter (only in 5' direction) for peak to be assigned to the upstream region:"
    doc: "Max distance from the promoter (only in 5' direction) for peak to be assigned to the upstream region."


outputs:

  filtered_file:
    type: File
    format: "http://edamontology.org/format_3003"
    label: "Filtered called peaks with the nearest genes assigned"
    doc: "Regions of interest formatted as headerless BED file with [chrom start end name]"
    outputSource: feature_select/filtered_file

  filtered_file_for_igv:
    type: File
    format: "http://edamontology.org/format_3003"
    label: "Set peaks from operator, in simple bed format."
    doc: "Regions of interest formatted as headerless BED file with [chrom start end]"
    outputSource: formatting_bed/filtered_file_for_igv
    'sd:visualPlugins':
    - igvbrowser:
        tab: 'IGV Genome Browser'
        id: 'igvbrowser'
        type: 'bed'
        name: "Set operated Peaks"
        displayMode: "COLLAPSE"
        height: 40

  annotated_peaks_file:
    type: File?
    format: "http://edamontology.org/format_3475"
    label: "gene annotated filtered peaks file"
    doc: "nearest gene annotation per peak [refseq_id gene_id txStart txEnd strand chrom start end length abssummit pileup log1-p foldenrich log10q region]"
    outputSource: island_intersect/result_file
    'sd:visualPlugins':
    - syncfusiongrid:
        tab: 'Annotated Peak Filtering Results'
        Title: 'Filtered peaks with nearest gene annotation'

  # bambai_pair:
  #   type: File
  #   format: "http://edamontology.org/format_2572"
  #   label: "Not changed coordinate sorted BAM and BAI index files"
  #   doc: "Not changed coordinate sorted BAM and BAI index files"
  #   outputSource: alignment_file

  filtering_stdout_log:
    type: File
    format: "http://edamontology.org/format_2330"
    label: "Filtering stdout log"
    doc: "Filtering stdout log"
    outputSource: feature_select/stdout_log

  filtering_stderr_log:
    type: File
    format: "http://edamontology.org/format_2330"
    label: "Filtering stderr log"
    doc: "Filtering stderr log"
    outputSource: feature_select/stderr_log


steps:

  feature_select:
    run: ../tools/feature-select-sql.cwl
    in:
      feature_file: feature_file
      sql_query: sql_query
      columns:
        source: columns
        valueFrom: $("DISTINCT " + self.join(", "))   # multiple peaks can have the same coordinates but different abssummit, so we need to use DISTINCT
      header: header
    out:
    - filtered_file
    - stdout_log
    - stderr_log

  formatting_bed:
    run:
      cwlVersion: v1.0
      class: CommandLineTool
      requirements:
      - class: ScatterFeatureRequirement
      - class: ShellCommandRequirement
      inputs:
        script:
          type: string?
          default: |
            # format for IGV
            awk -F'\t' '{if($3>$2){printf("%s\t%.0f\t%.0f\t%.0f\t%.0f\t%.0f\t0\t0\t0\t%s\n",$1,$2,$3,$3-$2+1,$2+(($3-$2)/2),"0","peak_"NR)}}' $0 > output-for-igv.tsv
            # format for island intersect tool
            awk -F'\t' 'BEGIN {print "chr\tstart\tend\tlength\tabs_summit\tpileup\t-log10(pvalue)\tfold_enrichment\t-log10(qvalue)\tname"};{if($3>$2){printf("%s\t%.0f\t%.0f\t%.0f\t%.0f\t%.0f\t0\t0\t0\t%s\n",$1,$2,$3,$3-$2+1,$2+(($3-$2)/2),"0","peak_"NR)}}' $0 > output-for-iaintersect.tsv
          inputBinding:
            position: 1
        headerless_bed:
          type: File
          inputBinding:
            position: 2
      outputs:
        filtered_file_for_igv:
          type: File
          outputBinding:
            glob: output-for-igv.tsv
        filtered_file_for_iaintersect:
          type: File
          outputBinding:
            glob: output-for-iaintersect.tsv
      baseCommand: ["bash", "-c"]
    in:
      headerless_bed: feature_select/filtered_file
    out:
    - filtered_file_for_igv
    - filtered_file_for_iaintersect

  island_intersect:
    label: "Peak annotation"
    doc: |
      Assigns nearest genes to peaks to explore the biological implication of the open
      chromatin binding sites.
    run: ../tools/iaintersect.cwl
    in:
      input_filename: formatting_bed/filtered_file_for_iaintersect
      annotation_filename: annotation_file
      promoter_bp: promoter_dist
      upstream_bp: upstream_dist
    out: [result_file, log_file]


$namespaces:
  s: http://schema.org/

$schemas:
- https://github.com/schemaorg/schemaorg/raw/main/data/releases/11.01/schemaorg-current-http.rdf

s:name: "Filter ChIP/ATAC peaks for Tag Density Profile or Motif Enrichment analyses"
label: "Filter ChIP/ATAC peaks for Tag Density Profile or Motif Enrichment analyses"
s:alternateName: "Filter ChIP/ATAC peaks for Tag Density Profile or Motif Enrichment analyses"

s:downloadUrl: https://raw.githubusercontent.com/datirium/workflows/master/workflows/filter-peaks-for-heatmap.cwl
s:codeRepository: https://github.com/datirium/workflows
s:license: http://www.apache.org/licenses/LICENSE-2.0

s:isPartOf:
  class: s:CreativeWork
  s:name: Common Workflow Language
  s:url: http://commonwl.org/

s:creator:
- class: s:Organization
  s:legalName: "Cincinnati Children's Hospital Medical Center"
  s:location:
  - class: s:PostalAddress
    s:addressCountry: "USA"
    s:addressLocality: "Cincinnati"
    s:addressRegion: "OH"
    s:postalCode: "45229"
    s:streetAddress: "3333 Burnet Ave"
    s:telephone: "+1(513)636-4200"
  s:logo: "https://www.cincinnatichildrens.org/-/media/cincinnati%20childrens/global%20shared/childrens-logo-new.png"
  s:department:
  - class: s:Organization
    s:legalName: "Allergy and Immunology"
    s:department:
    - class: s:Organization
      s:legalName: "Barski Research Lab"
      s:member:
      - class: s:Person
        s:name: Michael Kotliar
        s:email: mailto:misha.kotliar@gmail.com
        s:sameAs:
        - id: http://orcid.org/0000-0002-6486-3898


doc: |
  Filters ChIP/ATAC peaks with the neatest genes assigned for Tag Density Profile or Motif Enrichment analyses
  ============================================================================================================

  Tool filters output from any ChIP/ATAC pipeline to create a file with regions of interest for Tag Density
  Profile or Motif Enrichment analyses. Peaks with duplicated coordinates are discarded.

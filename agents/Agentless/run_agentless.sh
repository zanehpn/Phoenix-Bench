export OPENAI_API_BASE=https://api.openai.com/v1
export OPENAI_API_KEY=YOUR_OPENAI_API_KEY
export TREE_SITTER_VERILOG_SO=/workspace/phoenix-bench/Agentless/my-languages.so
export PYTHONPATH=$PYTHONPATH:$(pwd)
AGENTLESS_MODEL="${AGENTLESS_MODEL:-gpt-5.2}"
AGENTLESS_MODEL_DIR="${AGENTLESS_MODEL//\//__}"
AGENTLESS_BACKEND="${AGENTLESS_BACKEND:-}"

if [ -z "$AGENTLESS_BACKEND" ]; then
  if [[ "$AGENTLESS_MODEL" == *deepseek* ]]; then
    AGENTLESS_BACKEND="deepseek"
  else
    AGENTLESS_BACKEND="openai"
  fi
fi

echo "1"
python agentless/fl/localize.py --file_level \
                                --output_folder results/hwe-bench-lite/file_level \
                                --num_threads 10 \
                                --skip_existing \
                                --model "$AGENTLESS_MODEL" \
                                --backend "$AGENTLESS_BACKEND" \
				                --dataset_path /workspace/phoenix-bench/Agentless/agentless_dataset.json

echo "2"
python agentless/fl/localize.py --file_level \
                                --irrelevant \
                                --output_folder results/hwe-bench-lite/file_level_irrelevant \
                                --num_threads 10 \
                                --skip_existing \
                                --model "$AGENTLESS_MODEL" \
                                --backend "$AGENTLESS_BACKEND" \
				                --dataset_path /workspace/phoenix-bench/Agentless/agentless_dataset.json

echo "3"
python agentless/fl/retrieve.py --index_type simple \
                                --filter_type given_files \
                                --filter_file results/hwe-bench-lite/file_level_irrelevant/loc_outputs.jsonl \
                                --output_folder results/hwe-bench-lite/retrievel_embedding \
                                --persist_dir embedding/hwe-bench_simple \
                                --num_threads 10 \
				                --dataset_path /workspace/phoenix-bench/Agentless/agentless_dataset.json

echo "4"
python agentless/fl/combine.py  --retrieval_loc_file results/hwe-bench-lite/retrievel_embedding/retrieve_locs.jsonl \
                                --model_loc_file results/hwe-bench-lite/file_level/loc_outputs.jsonl \
                                --top_n 3 \
                                --output_folder results/hwe-bench-lite/file_level_combined 

echo "5"
python agentless/fl/localize.py --related_level \
                                --output_folder results/hwe-bench-lite/related_elements \
                                --top_n 3 \
                                --compress_assign \
                                --compress \
                                --start_file results/hwe-bench-lite/file_level_combined/combined_locs.jsonl \
                                --num_threads 10 \
                                --skip_existing \
                                --model "$AGENTLESS_MODEL" \
                                --backend "$AGENTLESS_BACKEND" \
				                --dataset_path /workspace/phoenix-bench/Agentless/agentless_dataset.json

echo "6"
python agentless/fl/localize.py --fine_grain_line_level \
                                --output_folder results/hwe-bench-lite/edit_location_samples \
                                --top_n 3 \
                                --compress \
                                --temperature 0.8 \
                                --num_samples 4 \
                                --start_file results/hwe-bench-lite/related_elements/loc_outputs.jsonl \
                                --num_threads 10 \
                                --skip_existing \
                                --model "$AGENTLESS_MODEL" \
                                --backend "$AGENTLESS_BACKEND" \
				                --dataset_path /workspace/phoenix-bench/Agentless/agentless_dataset.json

echo "7"
python agentless/fl/localize.py --merge \
                                --output_folder results/hwe-bench-lite/edit_location_individual \
                                --top_n 3 \
                                --num_samples 4 \
                                --start_file results/hwe-bench-lite/edit_location_samples/loc_outputs.jsonl \
                                --model "$AGENTLESS_MODEL" \
                                --backend "$AGENTLESS_BACKEND" \
				                --dataset_path /workspace/phoenix-bench/Agentless/agentless_dataset.json

echo "8"
while true; do
  timeout 300s python agentless/repair/repair.py --loc_file results/hwe-bench-lite/edit_location_individual/loc_merged_0-0_outputs.jsonl \
                                                --output_folder "results/hwe-bench-lite/repair_sample_verilog/${AGENTLESS_MODEL_DIR}" \
                                                --loc_interval \
                                                --top_n=3 \
                                                --context_window=10 \
                                                --max_samples 1  \
                                                --cot \
                                                --diff_format \
                                                --gen_and_process \
                                                --num_threads 2 \
                                                --model "$AGENTLESS_MODEL" \
                                                --backend "$AGENTLESS_BACKEND" \
						                                --dataset_path /workspace/phoenix-bench/Agentless/agentless_dataset.json
  status=$?
  if [ $status -eq 124 ]; then
    echo "Step 8 timed out after 300s, retrying..."
    continue
  fi
  if [ $status -ne 0 ]; then
    exit $status
  fi
  break
done

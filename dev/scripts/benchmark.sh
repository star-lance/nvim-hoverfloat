#!/bin/bash
# dev/scripts/benchmark.sh - Performance benchmarking

set -e

echo "📊 Running performance benchmarks..."

# Build first
./dev/scripts/build.sh

SOCKET_PATH="/tmp/nvim_context_bench.sock"

# Clean up function
cleanup() {
    pkill -f "context-tui-dev" 2>/dev/null || true
    rm -f "$SOCKET_PATH"
}
trap cleanup EXIT

echo "🚀 Starting TUI for benchmarking..."
./dev/bin/context-tui-dev "$SOCKET_PATH" &
TUI_PID=$!

sleep 2

if [ ! -S "$SOCKET_PATH" ]; then
    echo "❌ Failed to start TUI for benchmarking"
    exit 1
fi

echo "📈 Running message throughput test..."

# Test rapid message sending
start_time=$(date +%s%N)
for i in {1..100}; do
    ./dev/bin/mock-nvim-client scenario typescript_interface > /dev/null 2>&1
    sleep 0.01  # 10ms between messages
done
end_time=$(date +%s%N)

duration=$((($end_time - $start_time) / 1000000))  # Convert to milliseconds
throughput=$((100 * 1000 / $duration))

echo "✅ Throughput test complete:"
echo "   Messages: 100"
echo "   Duration: ${duration}ms"
echo "   Throughput: ~${throughput} msg/sec"

echo ""
echo "🧪 Testing memory usage..."
# Memory usage would require additional tooling
echo "   (Memory profiling requires pprof integration)"

echo ""
echo "📊 Benchmark complete!"


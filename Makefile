# Convect Root Makefile

.PHONY: all index bridge test test-c test-python test-integration bench clean

all: index bridge

index:
	$(MAKE) -C index all

bridge: index
	$(MAKE) -C bridge all

test: test-c test-python test-integration
	@echo ""
	@echo "======================================================"
	@echo " ALL CONVECT VERIFICATION TEST SUITES PASSED (100%)   "
	@echo "======================================================"

test-c: index
	$(MAKE) -C index test

test-python:
	python3 -m unittest discover -s tests/python -v

test-integration: index
	python3 -m unittest tests/integration/test_end_to_end.py -v

bench: index
	@echo "Running C Spatial Index Benchmark..."
	@clang -Wall -Wextra -Werror -O3 -std=c11 bench/benchmark_spatial.c index/build/libconvect_spatial.a -o bench/benchmark_spatial -lm
	@./bench/benchmark_spatial
	@rm -f bench/benchmark_spatial
	@echo ""
	@echo "Running Python End-to-End Throughput Benchmark..."
	@python3 bench/benchmark_throughput.py

clean:
	$(MAKE) -C index clean
	$(MAKE) -C bridge clean
	rm -rf build __pycache__ .pytest_cache tests/output

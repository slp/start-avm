.PHONY: clean

all: start_cvd_tools

start_cvd_tools: start_cvd_tools.c
	gcc -o $@ $< 

clean:
	rm -rf start_cvd_tools


.PHONY: clean

clean:
	rm -rf dist-newstyle dist test/data/*.tar* *.hp *.prof *.chi *.chs.h stack.yaml.lock .hspec-failures .stack-work
	touch .hspec-failures

MAKE	?= make
TYPST	?= typst
ZIP		?= zip

.PHONY: all zip

all:
	$(MAKE) -C Code

zip:
	$(MAKE) -C Code clean
	$(TYPST) compile docs/report.typ report.pdf
	$(ZIP) output.zip -r README.md report.pdf Code/

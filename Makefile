MAKE	?= make
TYPST	?= typst
ZIP		?= zip
GIT		?= git

.PHONY: all zip

all:
	$(MAKE) -C Code

zip:
	$(MAKE) -C Code clean
	$(TYPST) compile docs/report.typ report.pdf
	rm -f output.zip
	$(GIT) ls-files -z --cached --others --exclude-standard -- Code README.md | \
		xargs -0 $(ZIP) output.zip
	$(ZIP) output.zip report.pdf

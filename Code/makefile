CC       = gcc
AR       ?= ar
FLEX     ?= flex
BISON    ?= bison
AWK      ?= awk
CFLAGS   ?= -std=gnu11 -g -Wall -Wextra
ARFLAGS  = rcs
FILTER_AWK := feature-filter.awk

include features.mk
FEATURE_VARS := $(filter FEATURE_%,$(.VARIABLES))
FEATURE_DEFS := $(foreach v,$(FEATURE_VARS),-DCMM_$(patsubst FEATURE_%,%,$(v))=$($(v)))
override CPPFLAGS += -I. $(FEATURE_DEFS)

BUILD         := build
FEATURE_CONFIG := $(BUILD)/.feature-config
TARGET        := $(BUILD)/libcmm.a
PARSER        := parser
GRAMMAR_SOURCE := $(firstword $(shell find . -type f -name '*.y' -not -path './$(BUILD)/*'))
LEXER_SOURCE   := $(firstword $(shell find . -type f -name '*.l' -not -path './$(BUILD)/*'))
GRAMMAR_STEM   := $(basename $(notdir $(GRAMMAR_SOURCE)))
LEXER_STEM     := $(basename $(notdir $(LEXER_SOURCE)))
GRAMMAR_C      := $(BUILD)/$(GRAMMAR_STEM).tab.c
GRAMMAR_H      := $(BUILD)/$(GRAMMAR_STEM).tab.h
LEXER_C        := $(BUILD)/$(LEXER_STEM).lex.c
LEXER_FILTERED := $(BUILD)/$(LEXER_STEM).feature.l
GENERATED      := $(GRAMMAR_C) $(GRAMMAR_H) $(LEXER_C) $(LEXER_FILTERED)
C_SOURCES      := $(shell find . -type f -name '*.c' -not -path './$(BUILD)/*')
MAIN_SOURCE    := $(filter %/main.c main.c,$(C_SOURCES))
MAIN_OBJECT    := $(patsubst ./%.c,$(BUILD)/%.o,$(MAIN_SOURCE))
GRAMMAR_OBJECT := $(GRAMMAR_C:.c=.o)
LEXER_OBJECT   := $(LEXER_C:.c=.o)
SOURCE_OBJECTS := $(patsubst ./%.c,$(BUILD)/%.o,$(C_SOURCES))
LIB_OBJECTS    := $(GRAMMAR_OBJECT) $(LEXER_OBJECT) $(filter-out $(MAIN_OBJECT),$(SOURCE_OBJECTS))
ALL_OBJECTS    := $(sort $(GRAMMAR_OBJECT) $(LEXER_OBJECT) $(SOURCE_OBJECTS))
DEPFILES       := $(ALL_OBJECTS:.o=.d)
CDB            := compile_commands.json
CDB_SOURCES    := $(C_SOURCES) $(GRAMMAR_C) $(LEXER_C)

all: parser
test: $(PARSER)
	cd .. && $(foreach v,$(FEATURE_VARS),$(v)=$($(v))) sh tests/run.sh Code/$(PARSER)



$(BUILD):
	mkdir -p $@

.PHONY: FORCE
FORCE:

$(FEATURE_CONFIG): FORCE | $(BUILD)
	@printf '%s\n' '$(FEATURE_DEFS)' > $@.tmp
	@if ! cmp -s $@.tmp $@; then mv $@.tmp $@; else $(RM) $@.tmp; fi

$(ALL_OBJECTS): features.mk $(FEATURE_CONFIG)

$(PARSER): $(MAIN_OBJECT) $(TARGET)
	$(CC) $(LDFLAGS) $(CFLAGS) -o $@ $^

$(TARGET): $(LIB_OBJECTS)
	$(AR) $(ARFLAGS) $@ $^

$(GRAMMAR_C) $(GRAMMAR_H) &: $(GRAMMAR_SOURCE) | $(BUILD)
	$(BISON) $(BISONFLAGS) --defines=$(GRAMMAR_H) -o $(GRAMMAR_C) $<

$(LEXER_FILTERED): $(LEXER_SOURCE) $(FILTER_AWK) $(FEATURE_CONFIG) | $(BUILD)
	$(foreach v,$(FEATURE_VARS),$(v)=$($(v))) $(AWK) -f $(FILTER_AWK) $< > $@

$(LEXER_C): $(LEXER_FILTERED) $(GRAMMAR_H) | $(BUILD)
	$(FLEX) $(FLEXFLAGS) -o $@ $<

$(GRAMMAR_OBJECT): $(GRAMMAR_C) $(GRAMMAR_H)
	$(CC) $(CPPFLAGS) -I$(BUILD) $(CFLAGS) -MMD -MP -c $< -o $@

$(LEXER_OBJECT): $(LEXER_C) $(GRAMMAR_H)
	$(CC) $(CPPFLAGS) -I$(BUILD) -include $(GRAMMAR_H) $(CFLAGS) -MMD -MP -c $< -o $@

$(MAIN_OBJECT): $(MAIN_SOURCE) $(GRAMMAR_H) | $(BUILD)
	mkdir -p $(dir $@)
	$(CC) $(CPPFLAGS) -I$(BUILD) -include $(GRAMMAR_H) $(CFLAGS) -MMD -MP -c $< -o $@

$(BUILD)/%.o: %.c | $(BUILD)
	mkdir -p $(dir $@)
	$(CC) $(CPPFLAGS) -I$(BUILD) $(CFLAGS) -MMD -MP -c $< -o $@

$(CDB): features.mk $(FEATURE_CONFIG)
	@{ printf '[\n'; first=1; \
	for f in $(CDB_SOURCES); do \
		flags='$(CPPFLAGS) -I$(BUILD) $(CFLAGS)'; \
		case "$$f" in $(MAIN_SOURCE)|$(LEXER_C)) flags="$$flags -include $(GRAMMAR_H)" ;; esac; \
		if [ $$first = 1 ]; then first=0; else printf ',\n'; fi; \
		printf '  {"directory": "%s", "file": "%s", "arguments": ["%s", "%s", "-c", "%s"]}' \
			"$(CURDIR)" "$$f" "$(CC)" "$$(printf '%s' "$$flags" | sed 's/ /", "/g')" "$$f"; \
	done; printf '\n]\n'; } > $@

.PHONY: compile_commands
compile_commands: $(CDB)

clean:
	$(RM) -r $(BUILD)
	$(RM) $(PARSER)

-include $(DEPFILES)

.DELETE_ON_ERROR:
.PHONY: all clean test


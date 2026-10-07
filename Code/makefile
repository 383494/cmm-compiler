CC       = gcc
AR       ?= ar
FLEX     ?= flex
BISON    ?= bison
CFLAGS   ?= -std=gnu11 -g -Wall -Wextra -Wpedantic
ARFLAGS  = rcs

include features.mk
FEATURE_VARS := $(filter FEATURE_%,$(.VARIABLES))
FEATURE_DEFS := $(foreach v,$(FEATURE_VARS),-DCMM_$(patsubst FEATURE_%,%,$(v))=$($(v)))
override CPPFLAGS += $(FEATURE_DEFS)
ifneq ($(filter $(FEATURE_ENABLE_COMMENTS),0 1),$(FEATURE_ENABLE_COMMENTS))
$(error FEATURE_ENABLE_COMMENTS must be 0 or 1)
endif

BUILD         := build
TARGET        := $(BUILD)/libcmm.a
PARSER        := parser
GRAMMAR_SOURCE := $(firstword $(shell find . -type f -name '*.y' -not -path './$(BUILD)/*'))
LEXER_SOURCE   := $(firstword $(shell find . -type f -name '*.l' -not -path './$(BUILD)/*'))
GRAMMAR_STEM   := $(basename $(notdir $(GRAMMAR_SOURCE)))
LEXER_STEM     := $(basename $(notdir $(LEXER_SOURCE)))
GRAMMAR_C      := $(BUILD)/$(GRAMMAR_STEM).tab.c
GRAMMAR_H      := $(BUILD)/$(GRAMMAR_STEM).tab.h
LEXER_C        := $(BUILD)/$(LEXER_STEM).lex.c
GENERATED      := $(GRAMMAR_C) $(GRAMMAR_H) $(LEXER_C)
C_SOURCES      := $(shell find . -type f -name '*.c' -not -path './$(BUILD)/*')
MAIN_SOURCE    := $(filter %/main.c main.c,$(C_SOURCES))
MAIN_OBJECT    := $(patsubst ./%.c,$(BUILD)/%.o,$(MAIN_SOURCE))
GRAMMAR_OBJECT := $(GRAMMAR_C:.c=.o)
LEXER_OBJECT   := $(LEXER_C:.c=.o)
SOURCE_OBJECTS := $(patsubst ./%.c,$(BUILD)/%.o,$(C_SOURCES))
LIB_OBJECTS    := $(GRAMMAR_OBJECT) $(LEXER_OBJECT) $(filter-out $(MAIN_OBJECT),$(SOURCE_OBJECTS))
ALL_OBJECTS    := $(sort $(GRAMMAR_OBJECT) $(LEXER_OBJECT) $(SOURCE_OBJECTS))
DEPFILES       := $(ALL_OBJECTS:.o=.d)

all: parser


$(BUILD):
	mkdir -p $@

$(ALL_OBJECTS): features.mk

$(PARSER): $(MAIN_OBJECT) $(TARGET)
	$(CC) $(LDFLAGS) $(CFLAGS) -o $@ $^

$(TARGET): $(LIB_OBJECTS)
	$(AR) $(ARFLAGS) $@ $^

$(GRAMMAR_C) $(GRAMMAR_H) &: $(GRAMMAR_SOURCE) | $(BUILD)
	$(BISON) $(BISONFLAGS) --defines=$(GRAMMAR_H) -o $(GRAMMAR_C) $<

$(LEXER_C): $(LEXER_SOURCE) $(GRAMMAR_H) | $(BUILD)
	$(FLEX) $(FLEXFLAGS) -o $@ $<

$(GRAMMAR_OBJECT): $(GRAMMAR_C) $(GRAMMAR_H)
	$(CC) $(CPPFLAGS) -I. -I$(BUILD) $(CFLAGS) -MMD -MP -c $< -o $@

$(LEXER_OBJECT): $(LEXER_C) $(GRAMMAR_H)
	$(CC) $(CPPFLAGS) -I. -I$(BUILD) -include $(GRAMMAR_H) $(CFLAGS) -MMD -MP -c $< -o $@

$(MAIN_OBJECT): $(MAIN_SOURCE) $(GRAMMAR_H) | $(BUILD)
	mkdir -p $(dir $@)
	$(CC) $(CPPFLAGS) -I. -I$(BUILD) -include $(GRAMMAR_H) $(CFLAGS) -MMD -MP -c $< -o $@

$(BUILD)/%.o: %.c | $(BUILD)
	mkdir -p $(dir $@)
	$(CC) $(CPPFLAGS) -I. -I$(BUILD) $(CFLAGS) -MMD -MP -c $< -o $@

clean:
	$(RM) -r $(BUILD)
	$(RM) $(PARSER)

-include $(DEPFILES)

.DELETE_ON_ERROR:
.PHONY: all clean


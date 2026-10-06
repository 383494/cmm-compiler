#pragma once

typedef struct List {
	void *data;
	struct List *nxt;
} List;

List *list_push_front(List *head, void *data);
List *list_init(void *buf, List *data, List *nxt);

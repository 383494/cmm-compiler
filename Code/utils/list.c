#include "list.h"

List *list_init(void *buf, List *data, List *nxt) {
	List *list = (List *)buf;
	list->data = data;
	list->nxt = nxt;
	return list;
}

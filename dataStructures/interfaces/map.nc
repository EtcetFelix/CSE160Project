interface Map<t, s>{
command void insLocation(t llave, s loc);
    command void remLocation(t llave, s loc);
    command void printList(t llave);
    command bool listEmpty();
    command bool containsLoc(t llave, s loc);
    command bool containsList(t llave);
    command bool empty();
}

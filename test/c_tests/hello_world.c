void main(void){
  char hello[12] = {'h', 'e', 'l', 'l', 'o', ' ', 'w', 'o', 'r', 'l', 'd', '\0'};
  char *cursor = hello;

  char *VMEM = (char *) 32768;
  
  for (char i = 0; i < 25; i++){
    while (*cursor != 0){
      *VMEM = *cursor;
      VMEM++;
      cursor++;
    }
    cursor = hello;
  }
}

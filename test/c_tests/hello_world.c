void main(void){
  unsigned char *VMEM = (unsigned char *) 0x8000;
  
  for (char i = 0; i < 384; i++){
    *VMEM = 'x';
  }
}

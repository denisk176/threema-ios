//
//  Scrypt.h
//  Threema
//
//  Copyright © 2018 Threema AG. All rights reserved.
//

#ifndef Scrypt_h
#define Scrypt_h

#include <stdio.h>
#include <stdint.h>  /* uint8_t */

int getDerivedKey(char password[], char salt[], uint8_t out[64]);

#endif /* Scrypt_h */

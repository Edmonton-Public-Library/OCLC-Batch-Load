/*
 * To change this license header, choose License Headers in Project Properties.
 * To change this template file, choose Tools | Templates
 * and open the template in the editor.
 */

package epl.ftp;

import java.io.IOException;
import security.RandomString;

/**
 *
 * @author andrew
 */
class OCLCPasswordFile extends PasswordFileReader
{
    public static String PATH       = "password.txt";
    private final int MAX_PASSWORD  = 8;

    public OCLCPasswordFile() throws IOException
    {
        super(PATH);
    }
    
    @Override
    public String generateNewPassword()
    {
        // is 8 characters and must have numbers and letters.
        RandomString randomString = new RandomString(MAX_PASSWORD);
        // ensure that at least one char is a digit
        String newPassword = randomString.nextString();
        while (this.containsDigit(newPassword) == false)
        {
            newPassword = randomString.nextString();
        }
        return newPassword;
    }
    
    /**
     * This method ensures that all passwords that are generated include at least
     * one digit, an OCLC requirement.
     * @param word - string password that is tested for a digit.
     * @return true if the argument string contains a digit and false otherwise.
     */
    protected boolean containsDigit(String word)
    {
        for (int i = 0; i < MAX_PASSWORD; i++)
        {
            if (Character.isDigit(word.charAt(i)))
            {
                return true;
            }
        }
        return false;
    }
}

import bcrypt from 'bcryptjs';
import prisma from '../config/db';
import { generateToken } from '../utils/jwt';
import { generateUsername } from '../utils/usernameGenerator';

interface RegisterInput {
  username: string;
  email: string;
  password: string;
  firstName: string;
  lastName: string;
}

interface LoginInput {
  email: string;
  password: string;
}

interface UserResponse {
  id: string;
  username: string;
  email: string;
  firstName?: string ;
  lastName?: string ;
}

interface AuthResponse {
  user: UserResponse;
  token: string;
}

export const register = async ({
  email,
  password,
  firstName,
  lastName,
}: Omit<RegisterInput, 'username'>): Promise<AuthResponse> => {

    const existingUser = await prisma.user.findUnique({ where: { email } });
  if (existingUser) {
    throw new Error('Email already exists');
  }

  // console.log('JWT_SECRET:', process.env.JWT_SECRET);
 
  let username = generateUsername();
  while (await prisma.user.findUnique({ where: { username } })) {
    username = generateUsername();
  }


  const hashedPassword = await bcrypt.hash(password, 10);

  // Create user
  const user = await prisma.user.create({
    data: {
      username,
      email,
      password: hashedPassword,
      firstName,
      lastName,
    },
    select: { id: true, username: true, email: true, firstName: true, lastName: true },
  });

  // Generate JWT
  const token = generateToken(user.id);

  return { user, token };
};


export const login = async ({ email, password }: LoginInput): Promise<AuthResponse> => {
  // Find user by username
  const user = await prisma.user.findUnique({
    where: { email },
    select: { id: true, username: true, email: true, password: true, firstName: true, lastName: true },
  });
  if (!user) {
    throw new Error('Invalid credentials');
  }

  // Verify password
  const isValid = await bcrypt.compare(password, user.password);
  if (!isValid) {
    throw new Error('Invalid credentials');
  }

  // Generate JWT
  const token = generateToken(user.id);

  return {
     user: {
       id: user.id,
       username: user.username,
       email: user.email,
       firstName: user.firstName,
       lastName: user.lastName
       },
      token 
    };
};
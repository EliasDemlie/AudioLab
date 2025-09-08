import { Request, Response } from 'express';
import { register, login } from '../services/authService';

interface RegisterRequest extends Request {
  body: {
    username: string;
    email: string;
    password: string;
    firstName: string;
    lastName: string;
  };
}


interface LoginRequest extends Request {
  body: {
    email: string;
    password: string;
  };
}

export const registerController = async (req: RegisterRequest, res: Response) => {
  try {
    const {  email, password, firstName, lastName } = req.body;
    const response = await register({ email, password, firstName, lastName });
    res.status(201).json(response);
  } catch (error: any) {
    res.status(400).json({ error: error.message });
  }
};

export const loginController = async (req: LoginRequest, res: Response) => {
  try {
    const { email, password } = req.body;
    const response = await login({ email, password });
    res.json(response);
  } catch (error: any) {
    res.status(401).json({ error: error.message });
  }
};
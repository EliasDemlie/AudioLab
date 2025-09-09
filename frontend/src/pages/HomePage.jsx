import { Link } from 'react-router-dom';

function HomePage() {
  return (
    <div className="text-center mt-10 space-y-4">
      <h1 className="text-3xl font-bold">Welcome Home</h1>
      <p className="text-lg">This is the home page of your app.</p>
      <div className="space-x-4">
        <Link to="/login" className="text-blue-500 underline">
          Login
        </Link>
        <Link to="/register" className="text-blue-500 underline">
          Register
        </Link>
      </div>
    </div>
  );
}

export default HomePage;
